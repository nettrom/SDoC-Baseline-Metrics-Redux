# Event logging: https://wikitech.wikimedia.org/wiki/Analytics/Systems/EventLogging#Hadoop_&_Hive
# https://meta.wikimedia.org/wiki/Discovery/Analytics#Hadoop_Cluster
# spark documentation: https://wikitech.wikimedia.org/wiki/Analytics/Systems/Cluster/Spark

# fast way to know what the earliest day we have in the webrequest table:
# SHOW PARTITIONS wmf_raw.cirrussearchrequestset PARTITION(year='2017', hour='23');

# Start
# on stat1005
# spark2R --master yarn --executor-memory 2G --executor-cores 1 --driver-memory 4G
# Or on stat5, start an R session
Sys.setenv(SPARK_HOME="/usr/lib/spark2")
library(SparkR, lib.loc = c(file.path(Sys.getenv("SPARK_HOME"), "R", "lib")))
# Then start a spark session, see https://mapr.com/blog/sparkr-r-interactive-shell/
sparkR.session(master = "yarn", sparkConfig = list(spark.driver.memory = "2g"))

# Query
# Hive query doc: https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF
# Test on Hue
# event database
query <- "
SELECT CONCAT(year,'-',LPAD(month,2,'0'),'-',LPAD(day,2,'0')) as date, event.action, COUNT(*)
FROM event.testsearchsatisfaction2
WHERE year = 2018 AND month = 2 AND day = 1
  AND wiki = 'commonswiki'
  AND event.subTest IS NULL
  AND event.action IN('searchResultPage', 'click')
  AND event.source = 'fulltext'
  AND NOT useragent.is_bot
  AND CASE WHEN event.action = 'searchResultPage' THEN event.msToDisplayResults IS NOT NULL AND event.hitsReturned > 0
  WHEN event.action = 'click' THEN event.position IS NOT NULL AND event.position > -1
  ELSE TRUE
  END
GROUP BY year, month, day, event.action
"
result <- collect(sql(query))
