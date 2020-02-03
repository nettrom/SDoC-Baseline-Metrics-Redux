## Loading in the Jan 2020 dataset and cleaning it,
## then writing it out for further use.

library(data.table)

library(magrittr)
library(Rcpp)

## Note: import is a package, so this requires install.packages('import') to work
import::from(
    dplyr,
    keep_where = filter,
    select, group_by, ungroup,
    mutate, arrange, summarize, tally,
    case_when, if_else
)

library(scales)

fulltext_events_raw = fread("data/fulltext_events_raw_enwiki_commons_Jan2020.csv")

## remove the user_agent column, it's not used.
fulltext_events_raw[, user_agent := NULL]

#De-duplicating events
events <- fulltext_events_raw %>%
        mutate(
                dt = lubridate::ymd_hms(dt),
                date = as.Date(dt)
        ) %>%
        arrange(session_id, event_id, dt) %>%
        dplyr::distinct(session_id, event_id, .keep_all = TRUE)
rm(fulltext_events_raw)

## Fix double-escaped quotes in extraParams
events$extraParams = gsub("\"\"", "\"", events$extraParams)

# Sum all scroll check-in events and remove unnecessary check-ins.
events <- events %>%
        group_by(session_id, page_id) %>%
        mutate(scroll = ifelse(event_action == "checkin", sum(as.numeric(scroll)), as.numeric(scroll))) %>% # sum all scroll on visitPage and checkin events
        ungroup

events <- events[order(events$session_id, events$page_id, events$article_id, events$event_action, events$checkin, na.last = FALSE), ]

#remove extra check-ins
extra_checkins <- duplicated(events[, c("session_id", "page_id", "article_id", "event_action")], fromLast = TRUE) & events$event_action == "checkin"
events <- events[!extra_checkins, ]
rm(extra_checkins)

#Delete events with negative load time
events <- events %>%
        keep_where(is.na(load_time) | load_time >= 0)

#De-duplicating SERPs
SERPs <- events %>%
        keep_where(event_action == "searchResultPage") %>%
        arrange(session_id, dt) %>%
        select(c(session_id, page_id, query_hash)) %>%
        group_by(session_id, query_hash) %>%
        mutate(search_id = page_id[1]) %>%
        ungroup %>%
        select(c(session_id, page_id, search_id))

events <- events %>%
        dplyr::left_join(SERPs, by = c("session_id", "page_id"))
rm(SERPs)

# Removing events without an associated SERP (orphan clicks and check-ins)
n_event <- nrow(events)
events <- events %>%
        keep_where(!(is.na(search_id) & !(event_action %in% c("visitPage", "checkin")))) %>% # remove orphan click
        group_by(session_id) %>%
        keep_where("searchResultPage" %in% event_action) %>% # remove orphan "visitPage" and "checkin"
        ungroup
rm(n_event)

#Remove sessions with more than 50 searches. 
sessions_over50 <- events %>%
        group_by(date, session_id) %>%
        summarize(n_search = length(unique(search_id))) %>%
        keep_where(n_search > 50) %>%
        {.$session_id}

events <- events %>%
        keep_where(!(session_id %in% sessions_over50))
rm(sessions_over50)

#Check scroll on SERPs. 
events <- events %>%
        keep_where(!(event_action %in% c("visitPage", "checkin"))) %>%
        group_by(session_id, page_id) %>%
        summarize(n_scroll_serp = sum(scroll)) %>%
        ungroup %>%
        dplyr::right_join(events, by = c("session_id", "page_id"))

#Rename wiki column to clarify English Wikipedia vs Commons data.
events$wiki <- ifelse(events$wiki == "enwiki", "English Wikipedia", "Commons")

#Aggregating by search
searches <- events %>%
        keep_where(!(is.na(search_id))) %>% # remove visitPage and checkin events
        arrange(date, session_id, search_id, dt) %>%
        group_by(wiki, session_id, search_id) %>%
        summarize(
                date = date[1],
                dt = dt[1],
                `event scroll` = sum(n_scroll_serp, na.rm = TRUE) > 0,
                `got same-wiki results` = any(`some same-wiki results` == TRUE, na.rm = TRUE),
                engaged = any(event_action != "searchResultPage") || length(unique(page_id[event_action == "searchResultPage"])) > 1,
                `same-wiki clickthrough` = "click" %in% event_action,
                `other clickthrough` = sum(grepl("click", event_action) & event_action != "click"),
                `no. same-wiki results clicked` = length(unique(event_position[event_action == "click"])),
                `first clicked same-wiki results position` = ifelse(`same-wiki clickthrough`, event_position[event_action == "click"][1], NA), # event_position is 0-based
                `max clicked position (same-wiki)` = ifelse(`same-wiki clickthrough`, max(event_position[event_action == "click"], na.rm = TRUE), NA)
        ) %>%
        ungroup

#Aggregating by visited page (after clickthrough)
visitedPages <- events %>%
        arrange(date, session_id, page_id, dt) %>%
        group_by(wiki, session_id, page_id) %>%
        keep_where("visitPage" %in% event_action) %>% # keep only checkin and visitPage action
        summarize(
                dt = dt[1],
                position = na.omit(event_position)[1][1],
                dwell_time = ifelse("checkin" %in% event_action, max(checkin, na.rm = TRUE), 0),
                scroll = sum(scroll) > 0,
                status = ifelse(dwell_time == "420", 1, 2)
        ) %>%
        ungroup

visitedPages$dwell_time[is.na(visitedPages$dwell_time)] <- 0

## see https://github.com/wikimedia/wikimedia-discovery-polloi
## for how to install polloi

#Processing SERP offset data
parse_extraParams <- function(extraParams, action){
        if (extraParams == "{}") {
                if (all(action %in% c("hover-on", "hover-off"))) {
                        return(list(hoverId = NA, section = NA, results = NA))
                } else if (all(action %in% c("esclick"))) {
                        return(list(hoverId = NA, section = NA, result = NA))
                } else if (all(action %in% c("searchResultPage"))) {
                        return(list(offset = NA, iw = list(source = NA, position = NA)))
                } else {
                        return(NA)
                }
        } else {
                if (all(action %in% c("searchResultPage"))) {
                        output <- jsonlite::fromJSON(txt = as.character(extraParams), simplifyVector = TRUE)
                        offset <- polloi::data_select(is.null(output$offset), NA, output$offset)
                        iw <- polloi::data_select(is.null(output$iw), list(source = NA, position = NA), output$iw)
                        return(list(offset = offset, iw = iw))
                } else {
                        # "hover-on", "hover-off", "esclick"
                        return(jsonlite::fromJSON(txt = as.character(extraParams), simplifyVector = TRUE))
                }
        }
}

serp_offset <- events %>%
        # SERPs with 0 results will not have an offset in extraParams.
        keep_where(event_action == "searchResultPage", `some same-wiki results` == TRUE) %>%
        mutate(offset = purrr::map_int(extraParams, ~ parse_extraParams(.x, action = "searchResultPage")$offset)) %>%
        select(session_id, event_id, search_id, offset)

## write out all data
save(searches, file = "data/searches.Rdata")
save(serp_offset, file = "data/serp_offset.Rdata")
save(visitedPages, file = "data/visitedPages.Rdata")
