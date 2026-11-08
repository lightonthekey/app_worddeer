select id,
 replace(replace(replace(en,char(9),' '),char(10),' '),char(13),' '),
 replace(replace(replace(zh,char(9),' '),char(10),' '),char(13),' '),
 replace(replace(replace(ifnull(zh_detail,''),char(9),' '),char(10),' '),char(13),' '),
 ifnull(phonetic_us,''),
 ifnull(phonetic_uk,'')
from en_match_word where is_open=1 order by id;
