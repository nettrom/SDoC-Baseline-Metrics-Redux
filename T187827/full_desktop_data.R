message("Create an auto-closing SSH tunnel in the backgroud")
system("ssh -f -o ExitOnForwardFailure=yes stat1006.eqiad.wmnet -L 3307:analytics-slave.eqiad.wmnet:3306 sleep 10")
library(RMySQL)
con <- dbConnect(MySQL(), host = "127.0.0.1", group = "client", dbname = "log", port = 3307)


#query testsatisfaction dataset to obtain common and english wikipedia search data.
query <- "
SELECT
        timestamp,
        wiki,
        event_uniqueId AS event_id,
        event_pageViewId AS page_id,
        event_articleId AS article_id,
        event_searchSessionId AS session_id,
        event_action AS event,
        CASE
        WHEN event_position < 0 THEN NULL
        ELSE event_position
        END AS event_position,
        CASE
        WHEN event_action = 'searchResultPage' AND event_hitsReturned > 0 THEN 'TRUE'
        WHEN event_action = 'searchResultPage' AND event_hitsReturned IS NULL THEN 'FALSE'
        ELSE NULL
        END AS `some same-wiki results`,
        CASE
        WHEN event_action = 'searchResultPage' AND event_hitsReturned > -1 THEN event_hitsReturned
        WHEN event_action = 'searchResultPage' AND event_hitsReturned IS NULL THEN 0
        ELSE NULL
        END AS n_results,
        event_scroll,
        event_checkin,
        event_extraParams,
        event_msToDisplayResults AS load_time,
        userAgent AS user_agent
FROM TestSearchSatisfaction2_16909631
WHERE wiki IN ('commonswiki', 'enwiki')
AND LEFT(timestamp, 6) >= '201802'
AND INSTR(userAgent, '\"is_bot\": false') > 0
AND event_source = 'fulltext'
AND event_subTest IS NULL
AND CASE WHEN event_action = 'searchResultPage' THEN event_msToDisplayResults IS NOT NULL
    WHEN event_action IN ('click', 'iwclick', 'ssclick') THEN event_position IS NOT NULL AND event_position > -1
    WHEN event_action = 'visitPage' THEN event_pageViewId IS NOT NULL
    WHEN event_action = 'checkin' THEN event_checkin IS NOT NULL AND event_pageViewId IS NOT NULL
    ELSE TRUE
    END
;
"

fulltext_events_raw <- wmf::mysql_read(query, "log", con)
wmf::mysql_disconnect(con)
save(fulltext_events_raw, file = "data/fulltext_events_raw_enwiki_commons.RData")

#install required packages
install.packages("import")
library(magrittr)
library(ggplot2)
library(Rcpp)
import::from(
        dplyr,
        keep_where = filter, select,
        group_by, ungroup,
        mutate, arrange, summarize, tally,
        case_when, if_else
)

# Clean Data

load("data/fulltext_events_raw_enwiki_commons.RData")
events <- fulltext_events_raw
#De-duplicating events
events <- events %>%
        mutate(
                timestamp = lubridate::ymd_hms(timestamp),
                date = as.Date(timestamp)
        ) %>%
        arrange(session_id, event_id, timestamp) %>%
        dplyr::distinct(session_id, event_id, .keep_all = TRUE)
rm(fulltext_events_raw) 


# Sum all scroll check-in events and remove unnecessary check-ins.
events <- events %>%
        group_by(session_id, page_id) %>%
        mutate(event_scroll = ifelse(event == "checkin", sum(event_scroll), event_scroll)) %>% # sum all scroll on visitPage and checkin events
        ungroup

events <- events[order(events$session_id, events$page_id, events$article_id, events$event, events$event_checkin, na.last = FALSE), ]
#remove extra check-ins
extra_checkins <- duplicated(events[, c("session_id", "page_id", "article_id", "event")], fromLast = TRUE) & events$event == "checkin"
events <- events[!extra_checkins, ]
rm(extra_checkins)

#Delete events with negative load time
events <- events %>%
        keep_where(is.na(load_time) | load_time >= 0)

#De-duplicating SERPs
SERPs <- events %>%
        keep_where(event == "searchResultPage") %>%
        arrange(session_id, timestamp) %>%
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
        keep_where(!(is.na(search_id) & !(event %in% c("visitPage", "checkin")))) %>% # remove orphan click
        group_by(session_id) %>%
        keep_where("searchResultPage" %in% event) %>% # remove orphan "visitPage" and "checkin"
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
        keep_where(!(event %in% c("visitPage", "checkin"))) %>%
        group_by(session_id, page_id) %>%
        summarize(n_scroll_serp = sum(event_scroll)) %>%
        ungroup %>%
        dplyr::right_join(events, by = c("session_id", "page_id"))

#Rename wiki column to clarify English Wikipedia vs Commons data.
events$wiki <- ifelse(events$wiki == "enwiki", "English Wikipedia", "Commons")


#Aggregating by search
searches <- events %>%
        keep_where(!(is.na(search_id))) %>% # remove visitPage and checkin events
        arrange(date, session_id, search_id, timestamp) %>%
        group_by(wiki, session_id, search_id) %>%
        summarize(
                date = date[1],
                timestamp = timestamp[1],
                `got same-wiki results` = any(`some same-wiki results` == "TRUE", na.rm = TRUE),
                engaged = any(event != "searchResultPage") || length(unique(page_id[event == "searchResultPage"])) > 1,
                `same-wiki clickthrough` = "click" %in% event,
                `other clickthrough` = sum(grepl("click", event) & event != "click"),
                `no. same-wiki results clicked` = length(unique(event_position[event == "click"])),
                `first clicked same-wiki results position` = ifelse(`same-wiki clickthrough`, event_position[event == "click"][1], NA), # event_position is 0-based
                `max clicked position (same-wiki)` = ifelse(`same-wiki clickthrough`, max(event_position[event == "click"], na.rm = TRUE), NA)
        ) %>%
        ungroup

#Aggregating by visited page (after clickthrough)
visitedPages <- events %>%
        arrange(date, session_id, page_id, timestamp) %>%
        group_by(wiki, session_id, page_id) %>%
        keep_where("visitPage" %in% event) %>% # keep only checkin and visitPage action
        summarize(
                timestamp = timestamp[1],
                position = na.omit(event_position)[1][1],
                dwell_time = ifelse("checkin" %in% event, max(event_checkin, na.rm = TRUE), 0),
                scroll = sum(event_scroll) > 0,
                status = ifelse(dwell_time == "420", 1, 2)
        ) %>%
        ungroup

visitedPages$dwell_time[is.na(visitedPages$dwell_time)] <- 0

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
        keep_where(event == "searchResultPage", `some same-wiki results` == "TRUE") %>%
        mutate(offset = purrr::map_int(event_extraParams, ~ parse_extraParams(.x, action = "searchResultPage")$offset)) %>%
        select(session_id, event_id, search_id, offset)
