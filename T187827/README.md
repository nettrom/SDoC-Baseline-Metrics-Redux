# SDoC-Baseline-Metrics-Redux
Updating baseline search metrics for Wikimedia Structured Data on Commons (SDoC) project. Original analysis was done in November 2017 [T177534](https://phabricator.wikimedia.org/T177534). 

Ticket: [T187827](https://phabricator.wikimedia.org/T187827)

**February 2018 Report**. Update of baseline seach metrics using data collected in Feburary 2018. During this analysis, we discovered a drop in the in full-text search-wise clickthrough rate from 10.42% in November 2017 to only 3.17% in February 2018. Further investigation [T18675](https://phabricator.wikimedia.org/T187827) revealed this was due to image clicks not being recorded in event logging data (TestSearchSatisfaction2 table). 

**January 2019 Report**: Re-do of the analysis to see how metrics have changed following the deployment of a bug fix in September 2018. Data collected from October 2018 through January 2019.  

