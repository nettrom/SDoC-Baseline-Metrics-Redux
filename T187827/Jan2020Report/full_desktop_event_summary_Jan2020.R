## 0: Load in the cleaned data
load('data/searches.Rdata')
load('data/serp_offset.Rdata')
load('data/visitedPages.Rdata')

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
library(scales)
library(knitr)

## NOTE: this code requires binom and survminer packages to be installed
## survminer has dependencies (ggpubr, maxstat) that requires cowplot to be installed, but the current version
## doesn't work with R 3.3.3. Therefore, I used the following to install an older version
## of cowplot that works with our older R version:
## remotes::install_version('cowplot', '0.9.2')
## remotes::install_version('mvtnorm', '1.0-8')

## FIXME: make date settings configurable, particularly those mentioning date ranges of the data.

## 0.1 Some settings

fig_path <- file.path("figures")
plot_resolution <- 192

#1. Compare the desktop full-text search zero result rate on Commons vs English Wikipedia. Break down the number by day.

zrr <- searches %>%
        dplyr::filter(date < "2020-02-03") %>% #remove data from last day due to incomplete data on that day.
        group_by(wiki) %>%
        summarize(zero = sum(!`got same-wiki results`), n_search = dplyr::n()) %>%
        ungroup %>%
        cbind(
                as.data.frame(binom:::binom.bayes(x = .$zero, n = .$n_search, conf.level = 0.95, tol = 1e-9))
        )

p <-  zrr %>%
        ggplot(aes(x = wiki, y = mean, color = wiki, ymin = lower, ymax = upper)) +
        geom_linerange() +
        geom_label(aes(label = sprintf("%.2f%%", 100 * mean)), show.legend = FALSE) +
        ggplot2::scale_y_continuous(labels = scales::percent_format()) +
        ggplot2::scale_color_brewer("Wiki", palette = "Set1") +
        ggplot2::labs(x = NULL, color = "Group", y = "Zero results rate", title = "Proportion of full-text searches on desktop that did not yield any results", subtitle = "With 95% credible intervals. Data from 2019-11-05 to 2020-02-02") +
        wmf::theme_min() 

ggsave("zrr_all_Jan20.png", p, path = fig_path, units = "in", dpi = plot_resolution, height = 6, width = 10, limitsize = FALSE)
rm(p)

#Breakdown by day

p <- searches %>%
        dplyr::filter(date < "2020-02-03") %>% #remove data from last day due to incomplete data on that day.
        group_by(date, wiki) %>%
        summarize(n_search = dplyr::n(), zero = sum(!`got same-wiki results`)) %>%
        ungroup %>%
        cbind(
                as.data.frame(binom:::binom.bayes(x = .$zero, n = .$n_search, conf.level = 0.95, tol = 1e-9))
        ) %>%
        ggplot(aes(x = date, color = wiki, y = mean, ymin = lower, ymax = upper)) +
        geom_hline(data = zrr, aes(yintercept = mean, color = wiki), linetype = "dashed") +
        geom_ribbon(aes(ymin = lower, ymax = upper, fill = wiki), alpha = 0.1, color = NA) +
        geom_line() +
        scale_color_brewer("Wiki", palette = "Set1") +
        scale_fill_brewer("Wiki", palette = "Set1") +
        scale_x_date("Date", labels = date_format("%Y-%m-%d"), date_breaks = "2 weeks")  +
        scale_y_continuous("Zero results rate", labels = scales::percent_format()) +
        labs(title = "Daily full-text search-wise zero results rate on desktop", subtitle = "Dashed line marks the overall zero results rate.") +
        wmf::theme_min()

ggsave("daily_zrr_Jan20.png", p, path = fig_path, units = "in", dpi = plot_resolution, height = 6, width = 10, limitsize = FALSE)
rm(p)

#2. Compare the desktop full-text search clickthrough rate on Commons vs English Wikipedia. Break down the number by day.

## All ctr rates
ctr <- searches %>%
        dplyr::filter(date < "2020-02-03") %>% #remove data from last day due to incomplete data on that day.
        keep_where(`got same-wiki results` == TRUE) %>%
        group_by(wiki) %>%
        summarize(n_search = dplyr::n(), clickthroughs = sum(`same-wiki clickthrough`)) %>%
        ungroup %>%
        cbind(
                as.data.frame(binom:::binom.bayes(x = .$clickthroughs, n = .$n_search, conf.level = 0.95, tol = 1e-9))
        )

p <-  ctr %>%
        ggplot(aes(x = wiki, y = mean, color = wiki, ymin = lower, ymax = upper)) +
        geom_linerange() +
        geom_label(aes(label = sprintf("%.2f%%", 100 * mean)), show.legend = FALSE) +
        ggplot2::scale_y_continuous(labels = scales::percent_format()) +
        ggplot2::scale_color_brewer("Wiki", palette = "Set1") +
        ggplot2::labs(x = NULL, y = "Clickthrough rate", title = "Desktop full-text search results clickthrough rates", subtitle = "With 95% credible intervals. Data from 2019-11-05 to 2020-02-02.") +
        wmf::theme_min()
ggsave("ctr_all_Jan20.png", p, path = fig_path, units = "in", dpi = plot_resolution, height = 6, width = 10, limitsize = FALSE)
rm(p)


#Clickthrough rate broken down by day

p <- searches %>%
        dplyr::filter(date < "2020-02-03") %>% #remove data from last day due to incomplete data on that day.
        keep_where(`got same-wiki results` == TRUE) %>%
        group_by(wiki, date) %>%
        summarize(n_search = dplyr::n(), clickthroughs = sum(`same-wiki clickthrough`)) %>%
        ungroup %>%
        cbind(
                as.data.frame(binom:::binom.bayes(x = .$clickthroughs, n = .$n_search, conf.level = 0.95, tol = 1e-9))
        ) %>%
        ggplot(aes(x = date, color = wiki, y = mean, ymin = lower, ymax = upper)) +
        geom_hline(data = ctr, aes(yintercept = mean, color = wiki), linetype = "dashed") +
        geom_ribbon(aes(ymin = lower, ymax = upper, fill = wiki), alpha = 0.1, color = NA) +
        geom_line() +
        scale_color_brewer("Wiki", palette = "Set1") +
        scale_fill_brewer("Wiki", palette = "Set1") +
        scale_x_date("Date", labels = date_format("%Y-%m-%d"), date_breaks = "2 weeks")  +
        scale_y_continuous("Clickthrough rate", labels = scales::percent_format()) +
        labs(title = "Daily search-wise full-text clickthrough rates on desktop", subtitle = "Dashed line marks the overall clickthrough rate.") +
        wmf::theme_min()

ggsave("daily_ctr_Jan20.png", p, path = fig_path, units = "in", dpi = plot_resolution, height = 6, width = 10, limitsize = FALSE)
rm(p)

#Broken down by type of search page activity
p <- searches %>%
  dplyr::filter(date <= '2020-01-27')%>% #remove last few days due to incomplete data
  group_by(date) %>%
  summarize( 
    `All searches` = dplyr::n(),
    `All Search sessions (under 50 searches)` = length(unique(session_id)),
    `Searches with results` = sum(`got same-wiki results`),
    `Searches with clicks` = sum(`same-wiki clickthrough`),
    `Searches with no clicks` = sum(!`same-wiki clickthrough`),
    `Any event scroll` = sum(`event scroll`)
  ) %>%
  tidyr::gather(key = Type, value = count, -date) %>%
  ggplot(aes(x = date, y = count, colour = Type)) +
  geom_line(size = 1.2) +
  scale_x_date("Date", labels = date_format("%Y-%m-%d"), date_breaks = "2 weeks")  +
  scale_y_continuous(labels = polloi::compress, name = "Count") +
  labs(title = "Daily desktop full-text search activity on Commons") +
  wmf::theme_min()

ggsave("daily_search_activity_Jan20.png", p, path = fig_path, units = "in", dpi = plot_resolution, height = 6, width = 10, limitsize = FALSE)
rm(p)



#3. Compare the proportion of desktop full-text searches with clicks to see other pages of the search results on Commons vs English Wikipedia.
#All SERP offsets

offset_prop <- serp_offset %>%
        group_by(session_id, search_id) %>%
        summarize(`Any page-turning` = any(offset > 0)) %>%
        dplyr::right_join(searches, by = c("session_id", "search_id")) %>%
        group_by(wiki) %>%
        summarize(page_turn = sum(`Any page-turning`, na.rm = TRUE), n_search = dplyr::n()) %>%
        ungroup %>%
        cbind(
                as.data.frame(binom:::binom.bayes(x = .$page_turn, n = .$n_search, conf.level = 0.95, tol = 1e-9))
        )
p <- offset_prop %>%
        ggplot(aes(x = wiki, y = mean, color = wiki, ymin = lower, ymax = upper)) +
        geom_linerange() +
        geom_label(aes(label = sprintf("%.2f%%", 100 * mean)), show.legend = FALSE) +
        ggplot2::scale_y_continuous(labels = scales::percent_format()) +
        ggplot2::scale_color_brewer("Wiki", palette = "Set1") +
        ggplot2::labs(x = NULL, y = "Proportion of searches", title = "Proportion of desktop full-text searches with clicks to see other pages of the search results", subtitle = "With 95% credible intervals. Data from 2019-11-05 to 2020-02-02.") +
        wmf::theme_min(plot.title = element_text(size=14))

ggsave("serp_offset_all_Jan20.png", p, path = fig_path, units = "in", dpi = plot_resolution, height = 6, width = 10, limitsize = FALSE)
rm(p)


#Break down the daily offset by day.

p <- serp_offset %>%
        group_by(session_id, search_id) %>%
        summarize(`Any page-turning` = any(offset > 0)) %>%
        dplyr::right_join(searches, by = c("session_id", "search_id")) %>%
        dplyr::filter(date < "2020-02-03") %>% #remove data from last day due to incomplete data on that day.
        group_by(date, wiki) %>%
        summarize(page_turn = sum(`Any page-turning`, na.rm = TRUE), n_search = dplyr::n()) %>%
        ungroup %>%
        cbind(
                as.data.frame(binom:::binom.bayes(x = .$page_turn, n = .$n_search, conf.level = 0.95, tol = 1e-10))
        ) %>%
        ggplot(aes(x = date, color = wiki, y = mean, ymin = lower, ymax = upper)) +
        geom_hline(data = offset_prop, aes(yintercept = mean, color = wiki), linetype = "dashed") +
        geom_ribbon(aes(ymin = lower, ymax = upper, fill = wiki), alpha = 0.1, color = NA) +
        geom_line() +
        scale_color_brewer("Wiki", palette = "Set1") +
        scale_fill_brewer("Wiki", palette = "Set1") +
        scale_x_date("Date", labels = date_format("%Y-%m-%d"), date_breaks = "2 weeks")  +
        scale_y_continuous("Proportion of searches", labels = scales::percent_format()) +
        labs(title = "Proportion of desktop full-text searches with clicks to see other pages of the search results", subtitle = "Dashed line marks the overall proportion.") +
        wmf::theme_min(plot.title = element_text(size=13))

ggsave("daily_serp_offset_Jan20.png", p, path = fig_path, units = "in", dpi = plot_resolution, height = 6, width = 10, limitsize = FALSE)
rm(p)


#4. Compare the dwell time on articles after users clickthrough on Commons vs English Wikipedia.
temp <- visitedPages
#Create survival object
temp$SurvObj <- with(temp, survival::Surv(dwell_time, status == 2))
fit <- survival::survfit(SurvObj ~ wiki, data = temp)

ggsurv <- survminer::ggsurvplot(
        fit,
        conf.int = TRUE,
        xlab = "T (Dwell Time in seconds)",
        ylab = "Proportion of visits longer than T (P%)",
        surv.scale = "percent",
        color = "wiki",
        palette = "Set1",
        legend = "bottom",
        legend.title = "Wiki",
        ggtheme = wmf::theme_min()
)
p <- ggsurv$plot +
        labs(
                title = "Proportion of visited search results last longer than T",
                subtitle = "Full-text search on desktop. With 95% confidence intervals. Data from 2018-10-18 to 2019-01-16."
        )

ggsave("survival_visitedPages_all_Jan20.png", p, path = fig_path, units = "in", dpi = plot_resolution, height = 6, width = 10, limitsize = FALSE)
rm(p)

##Review of site visits broken down by the number of seconds a user has spent on a page.

##Breakdown by length of dwell time
dwell_time_bycheckin <- visitedPages %>%
        group_by(wiki, dwell_time) %>%
        summarize(visits = dplyr::n()) %>%
        mutate(dwell_time = factor(dwell_time)) %>%
        ungroup() %>%
        group_by(wiki) %>%
        mutate(allvisits= sum(visits)) %>%
        ungroup %>%
        cbind(
                as.data.frame(binom:::binom.bayes(x = .$visits, n = .$allvisits, conf.level = 0.95, tol = 1e-12))
        ) 
     
   
checkin_intervals <- c(
        `0` = "0-10s",
        `10` = "10-20s",
        `20` = "20-30s",
        `30` = "30-40s",
        `40` = "40-50s",
        `50` = "50-60s",
        `60` = "60-70s",
        `90` = "70-80s",
        `120` = "80-120s",
        `150` = "120-150s",
        `180` = "150-180s",
        `210` = "180-210s",
        `240` = "210-240s",
        `300` = "240-300s",
        `360` = "300-360s",
        `420` = "360-420s"
)

p <- dwell_time_bycheckin %>%
        ggplot(aes(x = wiki, y = mean, color = wiki, ymin = lower, ymax = upper)) +
        geom_linerange() +
        geom_label(aes(label = sprintf("%.2f%%", 100 * mean)), show.legend = FALSE) +
        scale_y_continuous(labels = scales::percent_format()) +
        facet_wrap(~ dwell_time, scale = "free_y", labeller =  as_labeller(checkin_intervals))+
        scale_color_brewer("Wiki", palette = "Set1") +
        theme(legend.position="bottom")  +
        labs(
                title = "Dwell time on articles after users clickthrough (broken down by check-in time)",
                subtitle = "Data from 2019-11-05 to 2020-02-02",
                y = "Proportion of visits.")
   

ggsave("dwell_time_bycheckin_Jan20.png", p, path = fig_path, units = "in", dpi = plot_resolution, height = 6, width = 10, limitsize = FALSE)
rm(p)
