-- query to obtain why files were deleted in 2017

SELECT 
 MONTH(DATE(LEFT(fa_deleted_timestamp, 8))) AS `month`,
   CASE WHEN fa_minor_mime = 'ogg' THEN 'audio'
       WHEN fa_minor_mime = 'pdf' THEN 'document'
       ELSE fa_major_mime END AS content_type,
  (
