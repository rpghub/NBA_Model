/***   Correct boxscore to say which LA Team   ***/

CREATE TABLE TEMP_LAGAMES AS(
SELECT g.*, bs.team
FROM stg.games g
	LEFT JOIN (SELECT DISTINCT bs.team, bs.match_id FROM stg.boxscore bs) bs ON g.match_id = bs.match_id
WHERE (home_team = 'Los Angeles' OR visit_team = 'Los Angeles'));

UPDATE stg.games g
	INNER JOIN 
      (SELECT l.match_id, COUNT(*) AS cnt FROM TEMP_LAGAMES l
      GROUP BY l.match_id) a 
      ON g.match_id = a.match_id
	INNER JOIN TEMP_LAGAMES l ON a.match_id = l.match_id
set g.home_team = l.team
WHERE a.cnt = 1 and g.home_team = 'Los Angeles';

UPDATE stg.games g
	INNER JOIN (SELECT l.match_id, COUNT(*) AS cnt FROM TEMP_LAGAMES l
    GROUP BY l.match_id) a 
    ON g.match_id = a.match_id
	INNER JOIN TEMP_LAGAMES l ON a.match_id = l.match_id
set g.visit_team = l.team
WHERE a.cnt = 1 and g.visit_team = 'Los Angeles';

UPDATE stg.games g
	INNER JOIN TEMP_LAGAMES l ON l.match_id = g.match_id
SET g.visit_team = l.team
WHERE g.home_team like '%Los Angeles%' AND g.visit_team like '%Los Angeles%'
	AND g.home_team != l.team; 

UPDATE stg.games g
	INNER JOIN TEMP_LAGAMES l ON l.match_id = g.match_id
SET g.home_team = l.team
WHERE g.home_team like '%Los Angeles%' AND g.visit_team like '%Los Angeles%'
	AND g.visit_team != l.team; 

-- mannual corrections to remaining problems
UPDATE stg.games SET home_team = 'Los Angeles Lakers' WHERE match_id = 240319013;
UPDATE stg.games SET home_team = 'Los Angeles Clippers' WHERE match_id = 250129012;
UPDATE stg.games SET home_team = 'Los Angeles Clippers' WHERE match_id = 320312012;
UPDATE stg.games SET visit_team = 'Los Angeles Clippers' WHERE match_id = 291106009;
UPDATE stg.games SET visit_team = 'Los Angeles Clippers' WHERE match_id = 310114009;

drop table TEMP_LAGAMES;

/***   create table of player names to pull out of pbp data   ***/

-- start with boxscore players
drop table if exists TEMP_PLAYERS;
CREATE TABLE TEMP_PLAYERS AS(
SELECT distinct bs.player, match_id
FROM stg.boxscore bs);

-- get additional players from pbp data
drop table if exists adtl_players;
CREATE TABLE ADTL_PLAYERS AS(
select a.* from(
SELECT DISTINCT g.home_team team, d.season_year,
	LEFT(p.home_action,LOCATE('enters the game',p.home_action)-2) player
FROM stg.play_by_play p 
	INNER JOIN stg.games g ON g.match_id = p.match_id
    INNER JOIN stg.ref_date d ON g.game_date = d.game_date
WHERE p.home_action LIKE '% enters the game for %'
UNION
SELECT DISTINCT g.visit_team team, d.season_year,
	LEFT(p.visit_action,LOCATE('enters the game',p.visit_action)-2) player
FROM stg.play_by_play p 
	INNER JOIN stg.games g ON g.match_id = p.match_id
    INNER JOIN stg.ref_date d ON g.game_date = d.game_date
WHERE p.visit_action LIKE '% enters the game for %'
UNION
SELECT DISTINCT  g.home_team team, d.season_year,
	CASE WHEN right(p.home_action,1) = '.' THEN
		MID(p.home_action,LOCATE('enters the game',p.home_action)+19,LENGTH(p.home_action)-1)
		ELSE MID(p.home_action,LOCATE('enters the game',p.home_action)+19,LENGTH(p.home_action))
        END player
FROM stg.play_by_play p 
	INNER JOIN stg.games g ON g.match_id = p.match_id
    INNER JOIN stg.ref_date d ON g.game_date = d.game_date
WHERE p.home_action LIKE '% enters the game for %'
UNION
SELECT DISTINCT  g.visit_team team, d.season_year,
	CASE WHEN right(p.visit_action,1) = '.' THEN
		MID(p.visit_action,LOCATE('enters the game',p.visit_action)+19,LENGTH(p.visit_action)-1)
		ELSE MID(p.visit_action,LOCATE('enters the game',p.visit_action)+19,LENGTH(p.visit_action))
        END player
FROM stg.play_by_play p 
	INNER JOIN stg.games g ON g.match_id = p.match_id
    INNER JOIN stg.ref_date d ON g.game_date = d.game_date
WHERE p.visit_action LIKE '% enters the game for %') as a
);

CREATE INDEX ADTL_PLAYERS_IDX ON ADTL_PLAYERS(team,season_year);

INSERT INTO TEMP_PLAYERS(player,match_id)
SELECT a.player, g.match_id
FROM stg.games g
    INNER JOIN (SELECT DISTINCT match_id FROM stg.boxscore) bs ON g.match_id = bs.match_id
	INNER JOIN stg.ref_date d ON g.game_date = d.game_date
    INNER JOIN stg.adtl_players a ON a.season_year = d.season_year AND a.team = g.home_team; 

INSERT INTO TEMP_PLAYERS(player,match_id)
SELECT a.player, g.match_id
FROM stg.games g
    INNER JOIN (SELECT DISTINCT match_id FROM stg.boxscore) bs ON g.match_id = bs.match_id
	INNER JOIN stg.ref_date d ON g.game_date = d.game_date
    INNER JOIN stg.adtl_players a ON a.season_year = d.season_year AND a.team = g.visit_team;

-- fix periods in names
CREATE TABLE TEMP_PLAYERS_UNIQUE AS(
SELECT DISTINCT CASE WHEN RIGHT(player,1) = '.' THEN
	lower(rtrim(ltrim(LEFT(player,length(player)-1))))
    ELSE lower(rtrim(ltrim(player))) 
    END player,
    match_id 
FROM TEMP_PLAYERS);

DROP TABLE TEMP_PLAYERS;
RENAME TABLE TEMP_PLAYERS_UNIQUE TO TEMP_PLAYERS;

CREATE INDEX TEMP_PLAYER_MATCH_IDX ON TEMP_PLAYERS (match_id);
CREATE INDEX TEMP_PLAYER_player_IDX ON TEMP_PLAYERS (player);

DROP TABLE adtl_players;

/***   pull player names out of pbp table   ***/

-- recast pbp table long 
drop table if exists temp_action;
CREATE TABLE TEMP_ACTION AS(
SELECT a.pbp_id,a.match_id,lower(a.action) as action, a.home
FROM(
SELECT p.pbp_id,p.match_id,p.home_action AS action, 1 as home 
FROM stg.play_by_play p
where p.home_action IS NOT NULL AND home_action != ''
UNION ALL
SELECT p.pbp_id,p.match_id,p.visit_action AS action, 0 as home 
FROM stg.play_by_play p
where p.visit_action IS NOT NULL AND visit_action != '') a
);

CREATE INDEX TEMP_ACTION_IDX ON TEMP_ACTION(match_id);
CREATE INDEX TEMP_ACTION_PBP_IDX on TEMP_ACTION(pbp_id);

-- up to 3 players in each action, remove one at a time
drop table if exists temp_action1;
CREATE TABLE TEMP_ACTION1 AS(
SELECT p.pbp_id
	,p.match_id
	,bs.player
    ,p.home
	,replace(p.action,bs.player,'<player1>') action
FROM TEMP_PLAYERS bs
    INNER JOIN stg.TEMP_ACTION p ON bs.match_id = p.match_id
WHERE locate(bs.player,p.action)>0
);

CREATE INDEX TEMP_ACTION1_PBP_IDX ON TEMP_ACTION1(pbp_id);
CREATE INDEX TEMP_ACTION1_match_IDX ON TEMP_ACTION1 (match_id);

drop table if exists temp_action2;
CREATE TABLE TEMP_ACTION2 AS(
SELECT p.pbp_id
	,p.match_id
	,bs.player
	,replace(p.action,bs.player,'<player2>') action
FROM TEMP_PLAYERS bs
    INNER JOIN TEMP_ACTION1 p ON bs.match_id = p.match_id
WHERE locate(bs.player,p.action)> locate('<player1>',p.action));

CREATE INDEX TEMP_ACTION2_IDX ON TEMP_ACTION2 (match_id);

drop table if exists temp_action3;
CREATE TABLE TEMP_ACTION3 AS(
SELECT p.pbp_id
	,p.match_id
	,bs.player 
    ,replace(p.action,bs.player,'<player3>') action
FROM TEMP_PLAYERS bs
    INNER JOIN stg.TEMP_ACTION2 p ON bs.match_id = p.match_id
WHERE locate(bs.player,p.action)>locate('<player2>',p.action));

CREATE INDEX TEMP_ACTION1_PBP ON TEMP_ACTION1(pbp_id);
CREATE INDEX TEMP_ACTION2_PBP ON TEMP_ACTION2(pbp_id);
CREATE INDEX TEMP_ACTION3_PBP ON TEMP_ACTION3(pbp_id);

drop table if exists stg.TEMP_ACTION_FULL;
CREATE TABLE stg.TEMP_ACTION_FULL(pbp_id integer
    ,match_id integer
    ,team_id integer
    ,player1 varchar(60)
    ,player2 varchar(60)
    ,player3 varchar(60)
    ,action varchar(250)
);

-- create proc to combine tables in batches to avoid memory limits
drop procedure if exists stg.append_action;
delimiter //
create procedure append_action()
begin
	set @j = 1;
	while @j < 6000000 do 
		INSERT INTO stg.TEMP_ACTION_FULL
		SELECT distinct h1.pbp_id
			,h1.match_id
            ,t.team_id
			,h1.player as player1
			,h2.player as player2
			,h3.player as player3
			,CASE WHEN h3.action IS NOT NULL THEN
				replace(h3.action,lower(t.city_name),'<city>')
				WHEN h2.action IS NOT NULL THEN
				h2.action
				ELSE
				remove_lname(h1.player,replace(h1.action,lower(t.city_name),'<city>'))
				END action
		FROM stg.TEMP_ACTION1 h1
			INNER JOIN stg.games g ON h1.match_id = g.match_id
			INNER JOIN stg.ref_date d ON g.game_date = d.game_date
			INNER JOIN stg.ref_teams t ON d.season_year = t.season_year 
				AND ((g.home_team = lower(t.team_name) AND h1.home = 1)
					or (g.visit_team = lower(t.team_name) AND h1.home = 0))
			LEFT JOIN stg.TEMP_ACTION2 h2 ON h1.pbp_id = h2.pbp_id
			LEFT JOIN stg.TEMP_ACTION3 h3 ON h1.pbp_id = h3.pbp_id
		WHERE h1.pbp_id >= @j AND h1.pbp_id < (@j+100000)
			AND ((h2.player is null and h3.player is null)
				or (h1.player != h2.player AND h3.player is null) 
				or (h1.player != h2.player AND h2.player != h3.player AND h1.player != h3.player));
        set @j = @j + 100000;
	end while;
end //
delimiter ;

call append_action();

UPDATE stg.temp_action_full a
SET a.action = replace(a.action,'jr','');

UPDATE stg.temp_action_full a
SET a.action = replace(a.action,'iii','');

UPDATE stg.temp_action_full a
SET a.action = rtrim(ltrim(replace(a.action,'.','')));

drop table temp_action;
drop table temp_action1;
drop table temp_action2;
drop table temp_action3;

/***   create ref_player table   ***/
-- start with boxscore players
DROP TABLE IF EXISTS stg.TEMP_REF_PLAYER;
CREATE TABLE TEMP_REF_PLAYER AS(
SELECT DISTINCT t.team_id
	,t.season_year
    ,bs.player
    ,9999999 player_id
    ,1 isDefault
FROM stg.boxscore bs
 INNER JOIN stg.games g ON bs.match_id = g.match_id
 INNER JOIN stg.ref_date d ON g.game_date = d.game_date
 INNER JOIN stg.ref_teams t ON bs.team = t.team_name 
	AND d.season_year = t.season_year);
 
DROP TABLE IF EXISTS stg.TEMP_PLAYER_ID; 
CREATE TABLE TEMP_PLAYER_ID(
	player_id INT AUTO_INCREMENT PRIMARY KEY,
    player VARCHAR(60)
);

INSERT INTO TEMP_PLAYER_ID(player)
SELECT DISTINCT player
FROM stg.temp_ref_player;

UPDATE stg.temp_ref_player p
	INNER JOIN stg.temp_player_id i ON p.player = i.player
SET p.player_id = i.player_id;

-- use regular full text index as worked better for matching than ngram
CREATE FULLTEXT INDEX TEMP_REF_PLAYER_PLAY_FULL_IDX ON TEMP_REF_PLAYER(player);
CREATE INDEX TEMP_REF_PLAYER_IDX ON TEMP_REF_PLAYER(season_year,team_id);

-- get additional players from pbp data
drop table if exists adtl_players;
CREATE TABLE ADTL_PLAYERS AS(
select a.* from(
SELECT DISTINCT g.home_team team, d.season_year,
	LEFT(p.home_action,LOCATE('enters the game',p.home_action)-2) player
FROM stg.play_by_play p 
	INNER JOIN stg.games g ON g.match_id = p.match_id
    INNER JOIN stg.ref_date d ON g.game_date = d.game_date
WHERE p.home_action LIKE '% enters the game for %'
UNION
SELECT DISTINCT g.visit_team team, d.season_year,
	LEFT(p.visit_action,LOCATE('enters the game',p.visit_action)-2) player
FROM stg.play_by_play p 
	INNER JOIN stg.games g ON g.match_id = p.match_id
    INNER JOIN stg.ref_date d ON g.game_date = d.game_date
WHERE p.visit_action LIKE '% enters the game for %'
UNION
SELECT DISTINCT  g.home_team team, d.season_year,
	CASE WHEN right(p.home_action,1) = '.' THEN
		MID(p.home_action,LOCATE('enters the game',p.home_action)+19,LENGTH(p.home_action)-1)
		ELSE MID(p.home_action,LOCATE('enters the game',p.home_action)+19,LENGTH(p.home_action))
        END player
FROM stg.play_by_play p 
	INNER JOIN stg.games g ON g.match_id = p.match_id
    INNER JOIN stg.ref_date d ON g.game_date = d.game_date
WHERE p.home_action LIKE '% enters the game for %'
UNION
SELECT DISTINCT  g.visit_team team, d.season_year,
	CASE WHEN right(p.visit_action,1) = '.' THEN
		MID(p.visit_action,LOCATE('enters the game',p.visit_action)+19,LENGTH(p.visit_action)-1)
		ELSE MID(p.visit_action,LOCATE('enters the game',p.visit_action)+19,LENGTH(p.visit_action))
        END player
FROM stg.play_by_play p 
	INNER JOIN stg.games g ON g.match_id = p.match_id
    INNER JOIN stg.ref_date d ON g.game_date = d.game_date
WHERE p.visit_action LIKE '% enters the game for %') as a
);

CREATE INDEX ADTL_PLAYERS_IDX ON ADTL_PLAYERS(team,season_year);

DROP TABLE IF EXISTS TEMP_REF_PLAYER_ADT;
 CREATE TABLE TEMP_REF_PLAYER_ADT AS(
 SELECT DISTINCT t.team_id
	,t.season_year
    ,RTRIM(LTRIM(p.player)) player
 FROM stg.adtl_players p 
	INNER JOIN stg.ref_teams t ON p.team = t.team_name
		AND p.season_year = t.season_year);
 
 -- full text matching can only be done record by record so need function to get best match
 -- this will return the player_id of the closest name match
 DROP FUNCTION IF EXISTS match_player; 
 DELIMITER $$
 CREATE FUNCTION match_player(player_in VARCHAR(60)
	,team_id_in INT, season_year_in  INT)
 RETURNS INT
 BEGIN
    RETURN (SELECT player_id 
		   FROM stg.temp_ref_player p
           WHERE p.team_id = team_id_in
			AND p.season_year = season_year_in
            AND isDefault = 1
            AND MATCH(p.player) AGAINST(player_in)
		   ORDER BY -(MATCH(p.player) AGAINST(player_in))
           LIMIT 1);
 END; 
 $$
 DELIMITER ;
 
 -- match the additional players from the pbp data to the closest matching name from boxscore
 INSERT INTO temp_ref_player(team_id,season_year,player,player_id,isDefault)
 SELECT team_id
	,season_year
    ,player
    ,CASE WHEN MATCH_PLAYER(player,team_id,season_year) IS NULL THEN
		0
        ELSE MATCH_PLAYER(player,team_id,season_year) 
		END player_id
	,0 isDefault
 FROM stg.temp_ref_player_adt
 HAVING player_id > 0;
 
 DROP TABLE IF EXISTS stg.ref_player;
 CREATE TABLE stg.ref_player(
	ref_player_id INT AUTO_INCREMENT PRIMARY KEY
    ,player_id INT
    ,player VARCHAR(50)
    ,isDefault INT
    ,cnt INT
)ENGINE=INNODB DEFAULT CHARSET=UTF8;
 
 INSERT INTO stg.ref_player(player_id,player,isDefault,cnt)
 SELECT player_id
	,RTRIM(LTRIM(CASE WHEN RIGHT(player,1) = '.' THEN
		LEFT(player,LENGTH(player)-1)
        ELSE player
        END)) player
	, MAX(isDefault) isDefault, COUNT(*) cnt
 FROM temp_ref_player
 GROUP BY player_id
	,RTRIM(LTRIM(CASE WHEN RIGHT(player,1) = '.' THEN
		LEFT(player,LENGTH(player)-1)
        ELSE player
        END));
 
 CREATE INDEX ref_player_player_idx ON stg.ref_player(player);
 CREATE INDEX ref_player_player_id_idx ON stg.ref_player(player_id);
 CREATE INDEX ref_player_default_idx ON ref_player(isDefault);
 CREATE INDEX ref_player_all_idx ON ref_player(player_id, isDefault);
 
 -- correct players that are assigned to multiple player_ids
 DROP TABLE IF EXISTS problem_ids;
 CREATE TABLE problem_ids AS(
 SELECT p.*
 FROM stg.ref_player p
 INNER JOIN (
 SELECT player, COUNT(player_id) cnt FROM(SELECT DISTINCT player, player_id FROM stg.ref_player) a
 GROUP BY player
 HAVING cnt > 1) a ON p.player = a.player);
 
 UPDATE stg.ref_player p 
	INNER JOIN problem_ids pi ON p.ref_player_id = pi.ref_player_id 
 SET p.isDefault = -1
 WHERE pi.isDefault = 0;
 
 DELETE FROM stg.ref_player WHERE isDefault = -1;
 
 DROP TABLE TEMP_REF_PLAYER;
 DROP TABLE TEMP_PLAYER_ID;
 DROP TABLE TEMP_REF_PLAYER_ADT;
 DROP TABLE problem_ids;
 DROP TABLE adtl_players;

 -- manual corrections to player names 
 -- Fix Ron Artest to be matched with meta world peace
 -- FIRST VALUE IS PLAYER_ID AND WILL LIKELY NEED TO BE CHANGED IN FUTURE RUNS!
 DELETE FROM ref_player WHERE ref_player_id = 748;
 INSERT INTO ref_player(player_id, player, isDefault, cnt)  VALUES(171, 'Ron Artest', 0, 100);
 INSERT INTO ref_player(player_id, player, isDefault, cnt)  VALUES(902, 'Daniel Green', 0, 100);
 INSERT INTO ref_player(player_id, player, isDefault, cnt)  VALUES(733, 'J Barea', 0, 100);
 INSERT INTO ref_player(player_id, player, isDefault, cnt)  VALUES(733, 'Jose Juan Barea', 0, 100);
 INSERT INTO ref_player(player_id, player, isDefault, cnt)  VALUES(720, 'Louis Amundson', 0, 100);
 INSERT INTO ref_player(player_id, player, isDefault, cnt)  VALUES(698, 'Marcus Vinicius', 0, 100);
 INSERT INTO ref_player(player_id, player, isDefault, cnt) VALUES(143, 'nenê', 0, 100);
 
/***  create action table from temp action full with player_ids   ***/

CREATE INDEX TEMP_ACTION_FULL_ACTION_IDX ON stg.temp_action_full(action);
create index temp_action_full_pbp_idx on temp_action_full(pbp_id);
create index temp_action_full_player1_idx on temp_action_full(player1);
create index temp_action_full_player2_idx on temp_action_full(player2);
create index temp_action_full_player3_idx on temp_action_full(player3);

-- delete instances where player is player1 and player2
update stg.temp_action_full a 
  inner join ref_player p1 on a.player1 = p1.player
  inner join ref_player p2 on a.player2 = p2.player
set a.pbp_id = -1*a.pbp_id
where p1.player_id = p2.player_id and a.player3 is null;

-- delete instances where player repeated
update stg.temp_action_full a 
  inner join ref_player p1 on a.player1 = p1.player
  inner join ref_player p2 on a.player2 = p2.player
  inner join ref_player p3 on a.player3 = p3.player
set a.pbp_id = -1*pbp_id
where p1.player_id = p2.player_id or p1.player_id =  p3.player_id or p2.player_id = p3.player_id;

delete from temp_action_full where pbp_id < 0;

drop table if exists stg.action;
create table stg.action as(
select distinct af.pbp_id, af.match_id, af.team_id, p.qtr, p.game_time
	, p1.player_id player_id1,p2.player_id player_id2,p3.player_id player_id3
    , ra.action_grp_id action_id
from stg.temp_action_full af
	inner join stg.ref_player p1 on af.player1 = p1.player
    left join stg.ref_player p2 on af.player2 = p2.player
    left join stg.ref_player p3 on af.player3 = p3.player
	inner join stg.ref_action ra ON af.action = ra.action_txt
    left join stg.play_by_play p ON af.pbp_id = p.pbp_id);

CREATE INDEX action_pbp_id_idx ON stg.action(pbp_id);

drop table if exists action_bad;
create table action_bad as(
select pbp_id, count(*) cnt
from action 
group by pbp_id
having cnt > 1);

create index action_bab_pbp_idx on action_bad(pbp_id);

-- remove records with wesley person or marcus cousin
set @wperson = (select player_id from ref_player where player = 'Wesley Person');
set @mcousin = (select player_id from ref_player where player = 'Marcus Cousin');

update action a
  inner join action_bad ab on ab.pbp_id = a.pbp_id
set a.pbp_id = -1*a.pbp_id
where a.player_id1 in(@wperson,@mcousin) or a.player_id2  in(@wperson,@mcousin) 
  or a.player_id3  in(@wperson,@mcousin);

delete from action where pbp_id < 0;

CREATE INDEX action_action_id_idx ON stg.action(action_id);
CREATE INDEX action_player1_idx ON stg.action(player_id1);
CREATE INDEX action_player2_idx ON stg.action(player_id2);

drop table action_bad;
-- drop table temp_action_full;

/***   track which players are on court for each action    ***/
/***   start by getting qtr starting lineupes              ***/

-- combine list of all players with actions in the qtr
drop table if exists stg.temp_qtr_starters;
create table stg.temp_qtr_starters as(
  select *
  from(
  select distinct match_id,team_id,qtr, player_id1 player_id
  from stg.action
  union
  select distinct match_id,team_id,qtr, player_id2 player_id 
  from stg.action
  union
  select distinct match_id,team_id,qtr, player_id3 player_id 
  from stg.action) a
  where a.player_id is not null
);

-- players that enter without exiting are not starters
drop table if exists stg.temp_qtr_enter;
create table stg.temp_qtr_enter as(
  select *
  from(
  select  match_id,team_id,qtr, player_id1 player_id, min(pbp_id) pbp_id_min
  from stg.action a
    inner join stg.ref_action r on a.action_id = r.action_id 
  where subtype1 = 'enters'
  group by match_id,team_id,qtr, player_id1 
  union
  select  match_id,team_id,qtr, player_id2 player_id, min(pbp_id) pbp_id_min
  from stg.action a
    inner join stg.ref_action r on a.action_id = r.action_id 
  where subtype2 = 'enters'
  group by match_id,team_id,qtr, player_id2
  union
  select  match_id,team_id,qtr, player_id3 player_id, min(pbp_id) pbp_id_min
  from stg.action a
    inner join stg.ref_action r on a.action_id = r.action_id 
  where subtype3 = 'enters'
  group by match_id,team_id,qtr, player_id3) a
  where a.player_id is not null);  

drop table if exists stg.temp_qtr_exits;
create table stg.temp_qtr_exits as(
  select *
  from(
  select  match_id,team_id,qtr, player_id1 player_id, min(pbp_id) pbp_id_min
  from stg.action a
    inner join stg.ref_action r on a.action_id = r.action_id 
  where subtype1 = 'exits'
  group by match_id,team_id,qtr, player_id1 
  union
  select  match_id,team_id,qtr, player_id2 player_id, min(pbp_id) pbp_id_min
  from stg.action a
    inner join stg.ref_action r on a.action_id = r.action_id
  where subtype2 = 'exits'
  group by match_id,team_id,qtr, player_id2
  union
  select  match_id,team_id,qtr, player_id3 player_id, min(pbp_id) pbp_id_min
  from stg.action a
    inner join stg.ref_action r on a.action_id = r.action_id
  where subtype3 = 'exits'
  group by match_id,team_id,qtr, player_id3) a
  where a.player_id is not null);


drop table if exists stg.temp_team_players;
create table stg.temp_team_players as(
  select distinct p.player_id, bs.match_id, t.team_id
  from stg.boxscore bs
    inner join stg.games g on bs.match_id = g.match_id
    inner join stg.ref_date d on g.game_date = d.game_date
    inner join stg.ref_teams t on t.team_name = bs.team
		and t.season_year = d.season_year
	inner join stg.ref_player p on bs.player = p.player
  where bs.min_ is not null);

create index temp_qtr_starts_all_idx on stg.temp_qtr_starters(match_id,team_id,qtr,player_id);
create index temp_qtr_enters_all_idx on stg.temp_qtr_enter(match_id,team_id,qtr,player_id);
create index temp_qtr_exits_all_idx on stg.temp_qtr_exits(match_id,team_id,qtr,player_id);
create index temp_team_players_all_idx on stg.temp_team_players(match_id,team_id,player_id);

-- delete people who subed in
update stg.temp_qtr_starters q
	inner join stg.temp_qtr_enter e on q.match_id = e.match_id
		and q.team_id = e.team_id and q.qtr = e.qtr 
        and q.player_id = e.player_id
	left join stg.temp_qtr_exits ex on q.match_id = ex.match_id
		and q.team_id = ex.team_id and q.qtr = ex.qtr 
        and q.player_id = ex.player_id and ex.pbp_id_min < e.pbp_id_min
set q.player_id = -1*q.player_id
where ex.player_id is null;

delete from stg.temp_qtr_starters where player_id < 0;

-- delete players that are not on the team
update stg.temp_qtr_starters q
	left join stg.temp_team_players p on q.match_id = p.match_id
		and q.team_id = p.team_id and q.player_id = p.player_id
set q.player_id = -1*q.player_id
where p.player_id is null;

delete from stg.temp_qtr_starters where player_id < 0;

-- bad starting lineups
set @row_number := 0;
drop table if exists temp_roster_error;
create table temp_roster_error as(
  select @row_number := @row_number+1 as error_id, match_id,team_id,qtr, count(*) cnt
  from temp_qtr_starters q 
  group by q.match_id, team_id,qtr
  having cnt != 5);
  
drop table if exists temp_roster_error_players;
create table temp_roster_error_players as(
select distinct error_id, d.season_year, q.team_id,
	q.qtr, q.player_id, cnt
from stg.temp_qtr_starters q
  inner join temp_roster_error e on q.match_id = e.match_id
    and q.team_id = e.team_id and q.qtr = e.qtr
  inner join stg.games g on q.match_id = g.match_id
  inner join stg.ref_date d on g.game_date = d.game_date);

-- drop bad starting lineups
update temp_qtr_starters q
  inner join temp_roster_error e on q.match_id = e.match_id
    and q.team_id = e.team_id and q.qtr = e.qtr
set q.player_id = -1*q.player_id;

delete from stg.temp_qtr_starters where player_id < 0;

create index temp_roster_error_all_idx on temp_roster_error_players(season_year,team_id,qtr,player_id,cnt);

-- merge bad lineups with potential fixes
drop table if exists temp_roster_counts;
create table temp_roster_counts as(
select q.* ,e.cnt, e.error_id
from temp_qtr_starters q
  inner join stg.games g on q.match_id = g.match_id
  inner join stg.ref_date d on g.game_date = d.game_date	
  left join temp_roster_error_players e on d.season_year = e.season_year
   and q.team_id = e.team_id and q.qtr = e.qtr and q.player_id = e.player_id);

-- select rosters with most matching players
drop table if exists temp_roster_fix;
create table temp_roster_fix as(
select match_id,team_id,qtr,cnt,error_id
	,count(*) as matched_cnt
from temp_roster_counts
where error_id is not null
group by match_id,team_id,qtr,cnt, error_id
);

-- get most frequenct starting lineups
drop table if exists temp_full_roster;
create table temp_full_roster as(
select r1.match_id, r1.team_id, r1.qtr, d.season_year, r1.player_id player_id1
	,r2.player_id player_id2, r3.player_id player_id3, r4.player_id player_id4
    , r5.player_id player_id5
from temp_qtr_starters r1
    inner join stg.games g on r1.match_id = g.match_id
    inner join stg.ref_date d on g.game_date = d.game_date
	inner join temp_qtr_starters r2 on r1.match_id = r2.match_id 
		and r1.team_id = r2.team_id and r1.qtr = r2.qtr
	inner join temp_qtr_starters r3 on r1.match_id = r3.match_id 
		and r1.team_id = r3.team_id and r1.qtr = r3.qtr
	inner join temp_qtr_starters r4 on r1.match_id = r4.match_id 
		and r1.team_id = r4.team_id and r1.qtr = r4.qtr
	inner join temp_qtr_starters r5 on r1.match_id = r5.match_id 
		and r1.team_id = r5.team_id and r1.qtr = r5.qtr
where r1.player_id > r2.player_id
    and r2.player_id > r3.player_id
    and r3.player_id > r4.player_id
    and r4.player_id > r5.player_id);

create index temp_full_roster_all_idx on temp_full_roster(team_id, season_year, player_id1, player_id2,player_id3,player_id4,player_id5);

drop table if exists temp_full_roster_cnt;
create table temp_full_roster_cnt as(
select r.match_id,r.team_id,r.qtr, r1.cnt
from temp_full_roster r 
	inner join (
	select count(*) cnt
		,team_id, season_year, player_id1, player_id2,player_id3,player_id4,player_id5
	from temp_full_roster
    group by team_id, season_year, player_id1, player_id2,player_id3,player_id4,player_id5) r1
    on r.team_id = r1.team_id and r.season_year = r1.season_year and r.player_id1 = r1.player_id1
    and r.player_id2 = r1.player_id2 and r.player_id3 = r1.player_id3 
    and r.player_id4 = r1.player_id4 and r.player_id5 = r1.player_id5);

create index temp_full_roster_cnt_id_idx on temp_full_roster_cnt(match_id,team_id,qtr);

-- get a unique record with the max matching players
drop table if exists temp_roster_use;
create table temp_roster_use as(
select f.match_id, f.team_id, f.qtr, f.error_id 
from temp_roster_fix f 
  inner join (select max(matched_cnt) cnt_max
				, error_id
			 from temp_roster_fix
             group by error_id) f2
	on f.error_id = f2.error_id and f.matched_cnt = f2.cnt_max
    );

drop table if exists temp_roster_fix_final;
create table temp_roster_fix_final as(
select max(f2.match_id) match_id,f2.team_id,f2.qtr,f1.error_id
from temp_roster_use f1
inner join temp_full_roster_cnt f2 on f2.match_id = f1.match_id
		and f2.team_id = f1.team_id and f2.qtr = f1.qtr
inner join(
	select max(f.cnt) roster_cnt, error_id
	from temp_roster_use r
		inner join temp_full_roster_cnt f on f.match_id = r.match_id
			and f.team_id = r.team_id and f.qtr = r.qtr
	group by r.error_id) f3 
	on f3.error_id = f1.error_id and f3.roster_cnt = f2.cnt
group by f2.team_id,f2.qtr,f1.error_id);

insert into temp_qtr_starters
select e.match_id, e.team_id, e.qtr, s.player_id
from temp_roster_fix_final f 
	inner join temp_qtr_starters s on f.match_id = s.match_id
      and f.team_id = s.team_id and f.qtr = s.qtr
    inner join temp_roster_error e on f.error_id = e.error_id;

drop table if exists temp_roster_fix_final;
drop table if exists temp_roster_use;
drop table if exists temp_full_roster_cnt;
drop table if exists temp_full_roster;
drop table if exists temp_roster_fix;
drop table if exists temp_roster_counts;
drop table if exists temp_roster_error_players;
drop table if exists temp_roster_error;

/***   keep track of which players are in and out of play   ***/
drop table if exists stg.temp_subs;
create table stg.temp_subs(
   sub_id integer auto_increment primary key
   ,pbp_id integer
   ,match_id integer
   ,team_id integer
   ,qtr integer
   ,game_time datetime
   ,player_id integer
   ,action_id integer
   ,type varchar(30)
   ,subtype varchar(30)
);

insert into stg.temp_subs(pbp_id,match_id,team_id,qtr,game_time,player_id,action_id,type,subtype)
select a.*
from(
select min(pbp_id) pbp_id ,match_id, team_id , qtr ,max(game_time) game_time
	,null player_id ,null action_id ,null type
    ,null subtype
from stg.action
group by match_id, team_id, qtr
union
select pbp_id ,match_id, team_id ,qtr ,game_time ,player_id1 player_id
    ,a.action_id ,type1 type ,subtype1 subtype
from stg.action a
  inner join ref_action r on a.action_id = r.action_id 
where type1 = 'sub' 
union
select pbp_id ,match_id, team_id ,qtr ,game_time ,player_id2 player_id
    ,a.action_id ,type2 type ,subtype2 subtype
from stg.action a
  inner join ref_action r on a.action_id = r.action_id
where type2 = 'sub' 
union
select pbp_id ,match_id, team_id ,qtr ,game_time ,player_id3 player_id
    ,a.action_id ,type3 type ,subtype3 subtype
from stg.action a
  inner join ref_action r on a.action_id = r.action_id
where type3 = 'sub'  
)a
order by match_id, team_id, qtr, game_time desc;

create index temp_subs_all_idx on temp_subs(sub_id, match_id, team_id, qtr);

drop table if exists temp_sub_blocks;
create table temp_sub_blocks as(
select s1.match_id, s1.team_id, s1.qtr, s1.pbp_id pbp_id_start
	,case when s2.pbp_id is null then
		999000000
	    else s2.pbp_id 
        end pbp_id_end
	, s1.sub_id 
from stg.temp_subs s1
	LEFT JOIN stg.temp_subs s2 ON s1.sub_id + 1 = s2.sub_id
		AND s1.match_id = s2.match_id AND s1.team_id = s2.team_id
        AND s1.qtr = s2.qtr	
where (s1.pbp_id != s2.pbp_id OR s2.pbp_id is null) 
order by s1.match_id, s1.team_id, s1.qtr, s1.game_time desc);

create index temp_sub_blocks_id_idx on temp_sub_blocks(sub_id);
create index temp_sub_blocks_all_idx on temp_sub_blocks(team_id,match_id,sub_id,qtr);
create index temp_subs_subtype_pbp_idx on temp_subs(pbp_id,subtype);

drop table if exists temp_active_players;
create table temp_active_players(
	player_id int,
    sub_id int
);


-- function to loop through each sub block and keep put in or take out
-- players as they sub in and out
drop function if exists fill_players;
DELIMITER $$
create function fill_players(team_id_in integer, match_id_in integer,qtr_in integer)
returns int deterministic
begin
	drop temporary table if exists curr_lineup;
	create temporary table curr_lineup(player_id int unique);
	set @id = (select min(sub_id) from stg.temp_sub_blocks 
		where team_id = team_id_in and match_id = match_id_in and qtr = qtr_in);
	set @id_max = (select max(sub_id) from stg.temp_sub_blocks
		where team_id = team_id_in and match_id = match_id_in and qtr = qtr_in);
	-- fill with starters first
    insert ignore into curr_lineup 
    select s.player_id 
    from stg.temp_qtr_starters s 
    where s.match_id = match_id_in and s.team_id = team_id_in and qtr = qtr_in;
    -- loop through subs
    while @id <= @id_max do
		insert into temp_active_players 
		select player_id, @id sub_id from curr_lineup;
        -- get the next sub pbp_id
        set @pbp_id = (select pbp_id_end from temp_sub_blocks where sub_id = @id);
        -- delete playes that leave
        update curr_lineup c
			inner join temp_subs s on s.player_id = c.player_id
        set c.player_id = -1*c.player_id
		where subtype in('exits','ejection')
			and pbp_id =  @pbp_id;
        delete from curr_lineup where player_id <0 ;
        -- add players that enter
        insert ignore into curr_lineup 
        select s.player_id
        from temp_subs s 
        where s.subtype in('enters') and s.pbp_id = @pbp_id;
        -- increment @id
        set @id = (select min(sub_id) from stg.temp_sub_blocks where sub_id > @id
			and team_id = team_id_in and match_id = match_id_in and qtr = qtr_in);
    end while;
    return 1;
end $$
delimiter ;

-- call the function to create the player tracking table
select max(a)
from (
select fill_players(team_id,match_id,qtr) rslt
from (select distinct team_id, match_id,qtr from stg.action) a);

create index temp_active_players_sub_idx on temp_active_players(sub_id);
create index temp_active_players_player_idx on temp_active_players(player_id);

-- diagnostic to check frequency of lineups by count of players
select a.cnt, count(*) as freq
from
(
select i.team_id, i.match_id, i.sub_id, count(player_id) cnt
from temp_active_players p
	inner join temp_sub_blocks i on p.sub_id = i.sub_id
group by i.team_id, i.sub_id, i.match_id
order by i.sub_id
) a
group by a.cnt;


/***   create table of all possible rosters (lineups) - 5 man down to 1 man   ***/
drop table if exists ref_roster;
CREATE TABLE ref_roster(
  ref_roster_id int auto_increment primary key,
  roster_5_id int,
  roster_id int,
  roster_len int,
  team_id int,
  season_year int,
  player_id1 int,
  player_id2 int,
  player_id3 int,
  player_id4 int,
  player_id5 int);


insert into ref_roster(team_id,season_year, roster_len, player_id1,
  player_id2, player_id3, player_id4, player_id5)
select distinct b.team_id, d.season_year, 5 as roster_len, r1.player_id
	,r2.player_id, r3.player_id, r4.player_id, r5.player_id
from temp_active_players r1
	inner join temp_sub_blocks b on r1.sub_id = b.sub_id
    inner join stg.games g on b.match_id = g.match_id
    inner join stg.ref_date d on g.game_date = d.game_date
	inner join temp_active_players r2 on r1.sub_id = r2.sub_id
	inner join temp_active_players r3 on r1.sub_id = r3.sub_id 
	inner join temp_active_players r4 on r1.sub_id = r4.sub_id 
	inner join temp_active_players r5 on r1.sub_id = r5.sub_id 
where r1.player_id > r2.player_id
    and r2.player_id > r3.player_id
    and r3.player_id > r4.player_id
    and r4.player_id > r5.player_id;
  
-- generate roster id    
update ref_roster set roster_5_id = ref_roster_id;

-- add 4 man rosters
insert into ref_roster(team_id,season_year,roster_5_id,roster_len, player_id1,
  player_id2, player_id3, player_id4, player_id5)
select r.team_id, r.season_year,roster_5_id,
  4 as roster_len,
  player_id1,
  player_id2, 
  player_id3, 
  player_id4, 
  0 as player_id5
from ref_roster r
where player_id5 >0;

insert into ref_roster(team_id,season_year,roster_5_id, roster_len, player_id1,
  player_id2, player_id3, player_id4, player_id5)
select r.team_id, r.season_year,roster_5_id,
  4 as roster_len,
  player_id1,
  player_id2, 
  player_id3, 
  player_id5 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id5 >0;

insert into ref_roster(team_id,season_year,roster_5_id,roster_len, player_id1,
  player_id2, player_id3, player_id4, player_id5)
select r.team_id, r.season_year,roster_5_id,
  4 as roster_len,
  player_id1,
  player_id2, 
  player_id4 as player_id3, 
  player_id5 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id5 >0;

insert into ref_roster(team_id,season_year,roster_5_id,roster_len, player_id1,
  player_id2, player_id3, player_id4, player_id5)
select r.team_id, r.season_year,roster_5_id,
  4 as roster_len,
  player_id1,
  player_id3 as player_id2, 
  player_id4 as player_id3, 
  player_id5 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id5 >0;

insert into ref_roster(team_id,season_year,roster_5_id, roster_len, player_id1,
  player_id2, player_id3, player_id4, player_id5)
select r.team_id, r.season_year,roster_5_id,
  4 as roster_len,
  player_id2 as player_id1,
  player_id3 as player_id2, 
  player_id4 as player_id3, 
  player_id5 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id5 >0;

-- add 3 man roster
insert into ref_roster(team_id,season_year,roster_5_id,roster_len, player_id1,
  player_id2, player_id3, player_id4, player_id5)
select distinct r.team_id, r.season_year,roster_5_id, 3 roster_len,
  player_id1,
  player_id2, 
  player_id3, 
  0 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id5 = 0 and player_id4 >0
union
select distinct r.team_id, r.season_year,roster_5_id, 3 roster_len,
  player_id1,
  player_id2, 
  player_id4 as player_id3, 
  0 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id5 = 0 and player_id4 >0
union
select distinct r.team_id, r.season_year,roster_5_id, 3 roster_len,
  player_id1,
  player_id3 as player_id2, 
  player_id4 as player_id3, 
  0 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id5 = 0 and player_id4 >0
union
select distinct r.team_id, r.season_year,roster_5_id, 3 roster_len,
  player_id2 as player_id1,
  player_id3 as player_id2, 
  player_id4 as player_id3, 
  0 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id5 = 0 and player_id4 >0;

-- add 2 man roster
insert into ref_roster(team_id,season_year,roster_5_id,roster_len, player_id1,
  player_id2, player_id3, player_id4, player_id5)
select distinct r.team_id, r.season_year,roster_5_id, 2 roster_len,
  player_id1,
  player_id2, 
  0 as player_id3, 
  0 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id4 = 0 and player_id3 >0
union
select distinct r.team_id, r.season_year,roster_5_id, 2 roster_len,
  player_id1,
  player_id3 as player_id2, 
  0  as player_id3, 
  0 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id4 = 0 and player_id3 >0
union
select distinct r.team_id, r.season_year,roster_5_id, 2 roster_len,
  player_id2 as player_id1,
  player_id3 as player_id2, 
  0 as player_id3, 
  0 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id4 = 0 and player_id3 >0;

-- add 1 man roster
insert into ref_roster(team_id,season_year,roster_5_id,roster_len, player_id1,
  player_id2, player_id3, player_id4, player_id5)
select distinct r.team_id, r.season_year,roster_5_id, 1 roster_len,
  player_id1,
  0 as player_id2, 
  0 as player_id3, 
  0 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id3 = 0 and player_id2 > 0
union
select distinct r.team_id, r.season_year,roster_5_id, 1 roster_len,
  player_id2 as player_id1,
  0 as player_id2, 
  0 as player_id3, 
  0 as player_id4, 
  0 as player_id5
from ref_roster r
where player_id3 = 0 and player_id2 > 0;

-- create roster ids
drop table if exists temp_roster_unique;
create table temp_roster_unique(
  roster_id int auto_increment primary key,
  roster_len int,
  team_id int,
  season_year int,
  player_id1 int,
  player_id2 int,
  player_id3 int,
  player_id4 int,
  player_id5 int);

create index ref_roster_len_idx on ref_roster(roster_len);
create index ref_roster_all_idx on ref_roster(roster_len,team_id,season_year,player_id1,player_id2,player_id3,player_id4,player_id5);

insert into temp_roster_unique(roster_len,team_id,season_year,player_id1,player_id2,player_id3,player_id4,player_id5)
select distinct roster_len,team_id,season_year,player_id1,player_id2,player_id3,player_id4,player_id5
from ref_roster
where roster_len < 5;

create index temp_roster_unique_all_idx on temp_roster_unique(roster_len,team_id,season_year,player_id1,player_id2,player_id3,player_id4,player_id5);

update ref_roster r 
  inner join temp_roster_unique tr on r.roster_len = tr.roster_len
    and r.team_id = tr.team_id and r.season_year = tr.season_year and r.player_id1 = tr.player_id1
    and r.player_id2 = tr.player_id2 and r.player_id3 = tr.player_id3 and r.player_id4 = tr.player_id4
    and r.player_id5 = tr.player_id5
set r.roster_id = tr.roster_id;

update ref_roster set roster_id = roster_5_id where roster_len = 5;

create index ref_roster_p1_idx on ref_roster(player_id1, roster_len);
create index ref_roster_team_idx on ref_roster(team_id, season_year); 
create index ref_roster_season_idx on ref_roster(season_year);


create index ref_roster_player_idx on ref_roster(player_id1, player_id2, player_id3, player_id4, player_id5, roster_len);

/***   return to player tracking and fix records to always have 5 palyers   ***/ 
drop table if exists temp_active_cnt;
create table temp_active_cnt(
	error_id int auto_increment primary key,
    sub_id int,
    cnt int);

insert into temp_active_cnt(sub_id,cnt)
select sub_id,count(*) cnt
from temp_active_players s
group by sub_id
having cnt != 5;

create index temp_active_cnt_sub_idx on temp_active_cnt(sub_id);
create index temp_active_cnt_error_idx on temp_active_cnt(error_id);

drop table if exists temp_active_errors;
create table temp_active_errors as(
select error_id, i.match_id, i.team_id, d.season_year, p.*, p1.cnt
from temp_active_players p 
	inner join temp_active_cnt p1 on p.sub_id = p1.sub_id
	inner join stg.temp_sub_blocks i ON p.sub_id = i.sub_id
	inner join stg.games g on i.match_id = g.match_id
	inner join stg.ref_date d on d.game_date = g.game_date);

-- delete bad records
update temp_active_players s
	inner join temp_active_cnt e on s.sub_id = e.sub_id
set s.player_id = -1*s.player_id;

delete from stg.temp_active_players where player_id <0;

create index temp_active_errors_all_idx on temp_active_errors(season_year,team_id,player_id);
create index temp_active_errors_error_idx on temp_active_errors(error_id);
create index temp_active_errors_player_idx on temp_active_errors(player_id);
create index temp_active_errors_cnt_idx on temp_active_errors(cnt);

-- get roster matches for error_ids
drop table if exists temp_active_errors_cnt;
create table temp_active_errors_cnt as(
select distinct r1.error_id, r1.team_id, r1.season_year, 5 as roster_len, r1.player_id player_id1
	,r2.player_id player_id2, r3.player_id player_id3, r4.player_id player_id4
    ,r5.player_id player_id5, r.roster_5_id as roster_id
from temp_active_errors r1
	inner join temp_active_errors r2 on r1.error_id = r2.error_id
	inner join temp_active_errors r3 on r1.error_id = r3.error_id 
	inner join temp_active_errors r4 on r1.error_id = r4.error_id 
	inner join temp_active_errors r5 on r1.error_id = r5.error_id
    inner join ref_roster r on r1.player_id = r.player_id1 
      and r2.player_id = r.player_id2 and r3.player_id = r.player_id3
      and r4.player_id = r.player_id4 and r5.player_id = r.player_id5
      and r1.team_id = r.team_id and r1.season_year = r.season_year
where r1.player_id > r2.player_id
    and r2.player_id > r3.player_id
    and r3.player_id > r4.player_id
    and r4.player_id > r5.player_id
	and r1.cnt > 5 and r.roster_len = 5);

drop table if exists used_errors;
create table used_errors as(select distinct error_id from temp_active_errors_cnt);    
create index used_errors_idx on used_errors(error_id);

insert into temp_active_errors_cnt
select distinct r1.error_id, r1.team_id, r1.season_year, 4 as roster_len, r1.player_id player_id1
	,r2.player_id player_id2, r3.player_id player_id3, r4.player_id player_id4
    ,0 player_id5, r.roster_id as roster_id
from temp_active_errors r1
	inner join temp_active_errors r2 on r1.error_id = r2.error_id
	inner join temp_active_errors r3 on r1.error_id = r3.error_id 
	inner join temp_active_errors r4 on r1.error_id = r4.error_id 
	inner join ref_roster r on r1.player_id = r.player_id1 
      and r2.player_id = r.player_id2 and r3.player_id = r.player_id3
      and r4.player_id = r.player_id4
      and r1.team_id = r.team_id and r1.season_year = r.season_year
	left join used_errors e on e.error_id = r1.error_id
where r1.player_id > r2.player_id
    and r2.player_id > r3.player_id
    and r3.player_id > r4.player_id
    and e.error_id is null
    and roster_len = 4;
    
drop table if exists used_errors;
create table used_errors as(select distinct error_id from temp_active_errors_cnt);    
create index used_errors_idx on used_errors(error_id);

insert into temp_active_errors_cnt
select distinct r1.error_id, r1.team_id, r1.season_year, 3 as roster_len, r1.player_id player_id1
	,r2.player_id player_id2, r3.player_id player_id3, 0 player_id4
    ,0 player_id5, r.roster_id as roster_id
from temp_active_errors r1
	inner join temp_active_errors r2 on r1.error_id = r2.error_id
	inner join temp_active_errors r3 on r1.error_id = r3.error_id 
	inner join ref_roster r on r1.player_id = r.player_id1 
      and r2.player_id = r.player_id2 and r3.player_id = r.player_id3
      and r1.team_id = r.team_id and r1.season_year = r.season_year
	left join used_errors e on e.error_id = r1.error_id
where r1.player_id > r2.player_id
    and r2.player_id > r3.player_id
	and e.error_id is null
    and roster_len = 3;

drop table if exists used_errors;
create table used_errors as(select distinct error_id from temp_active_errors_cnt);    
create index used_errors_idx on used_errors(error_id);
    
insert into temp_active_errors_cnt
select distinct r1.error_id, r1.team_id, r1.season_year, 2 as roster_len, r1.player_id player_id1
	,r2.player_id player_id2, 0 player_id3, 0 player_id4
    ,0 player_id5, r.roster_id as roster_id
from temp_active_errors r1
	inner join temp_active_errors r2 on r1.error_id = r2.error_id
	inner join temp_active_errors r3 on r1.error_id = r3.error_id 
	inner join ref_roster r on r1.player_id = r.player_id1 
      and r2.player_id = r.player_id2 and r1.team_id = r.team_id 
      and r1.season_year = r.season_year
	left join used_errors e on e.error_id = r1.error_id
where r1.player_id > r2.player_id
	and e.error_id is null
    and roster_len = 2;

drop table if exists used_errors;
create table used_errors as(select distinct error_id from temp_active_errors_cnt);    
create index used_errors_idx on used_errors(error_id);
    
insert into temp_active_errors_cnt
select distinct r1.error_id, r1.team_id, r1.season_year, 1 as roster_len, r1.player_id player_id1
	,0 player_id2, 0 player_id3, 0 player_id4
    ,0 player_id5, r.roster_id as roster_id
from temp_active_errors r1
	inner join temp_active_errors r2 on r1.error_id = r2.error_id
	inner join ref_roster r on r1.player_id = r.player_id1 
	  and r1.team_id = r.team_id and r1.season_year = r.season_year
	left join used_errors e on e.error_id = r1.error_id
where r1.cnt = 1 and r.roster_len = 1
	and e.error_id is null
    and roster_len = 1;

create index temp_active_errors_cnt_allroster_idx on temp_active_errors_cnt(team_id,season_year,roster_len,roster_id);

-- get most common rosters
drop table if exists temp_full_roster;
create table temp_full_roster as(
select b.sub_id, b.match_id, b.team_id, d.season_year, 5 as roster_len, r1.player_id player_id1
	,r2.player_id player_id2, r3.player_id player_id3, r4.player_id player_id4
    , r5.player_id player_id5, r.roster_5_id roster_id
from temp_active_players r1
	inner join temp_sub_blocks b on r1.sub_id = b.sub_id
    inner join stg.games g on b.match_id = g.match_id
    inner join stg.ref_date d on g.game_date = d.game_date
	inner join temp_active_players r2 on r1.sub_id = r2.sub_id
	inner join temp_active_players r3 on r1.sub_id = r3.sub_id 
	inner join temp_active_players r4 on r1.sub_id = r4.sub_id 
	inner join temp_active_players r5 on r1.sub_id = r5.sub_id
    inner join ref_roster r on r1.player_id = r.player_id1 
      and r2.player_id = r.player_id2 and r3.player_id = r.player_id3
      and r4.player_id = r.player_id4 and r5.player_id = r.player_id5
      and b.team_id = r.team_id and d.season_year = r.season_year
where r1.player_id > r2.player_id
    and r2.player_id > r3.player_id
    and r3.player_id > r4.player_id
    and r4.player_id > r5.player_id
    and r.roster_len = 5);
    
create index temp_full_roster_roster_idx on temp_full_roster(roster_id);
create index temp_full_roster_alll_idx on temp_full_roster(season_year,team_id,roster_id);

drop table if exists temp_full_roster_cnt;
create table temp_full_roster_cnt as(
	  select count(*) roster_used_cnt ,team_id, season_year, roster_id 
      from temp_full_roster
      group by team_id, season_year, roster_id);

create index temp_full_roster_cnt_all_idx on temp_full_roster_cnt(season_year,team_id,roster_id);

-- want to get linups that match active_errors lineups and have the most roster_used_cnt
drop table if exists temp_match_roster;
create table temp_match_roster as(
select distinct e.error_id, e.team_id, e.season_year, r.roster_5_id roster_id
 , case when rf.roster_used_cnt is null then 0 else rf.roster_used_cnt end roster_used_cnt
from temp_active_errors_cnt e
	inner join ref_roster r on e.team_id = r.team_id 
      and e.season_year = r.season_year and e.roster_id = r.roster_id
      and r.roster_len = e.roster_len
    left join temp_full_roster_cnt rf on e.team_id = rf.team_id
      and e.season_year = rf.season_year and r.roster_5_id = rf.roster_id);

create index temp_match_roster_error_idx on temp_match_roster(error_id);

drop table if exists temp_match_roster_max;
create table temp_match_roster_max as(
select max(r.roster_id) roster_id,r.season_year,r.team_id, r.error_id
from temp_match_roster r
	inner join (select max(roster_used_cnt) roster_used_cnt, error_id from temp_match_roster group by error_id) r1
		on r.error_id = r1.error_id and r.roster_used_cnt = r1.roster_used_cnt
group by r.season_year,r.team_id, r.error_id);

create index temp_match_roster_max_all_idx on temp_match_roster_max(team_id,season_year,roster_id);
create index temp_match_roster_max_error_idx on temp_match_roster_max(error_id);

drop index temp_active_players_sub_idx on temp_active_players;
drop index temp_active_players_player_idx on temp_active_players;

insert into temp_active_players(sub_id,player_id)
select a.sub_id, a.player_id
from (
select c.sub_id, r.player_id1 player_id
from temp_match_roster_max m
	inner join ref_roster r on m.team_id = r.team_id
      and r.season_year = m.season_year
      and m.roster_id = r.roster_id
	inner join temp_active_cnt c on m.error_id = c.error_id
where r.roster_len = 5
union
select c.sub_id, r.player_id2 player_id
from temp_match_roster_max m
	inner join ref_roster r on m.team_id = r.team_id
      and r.season_year = m.season_year
      and m.roster_id = r.roster_id
	inner join temp_active_cnt c on m.error_id = c.error_id
where r.roster_len = 5
union
select c.sub_id, r.player_id3 player_id
from temp_match_roster_max m
	inner join ref_roster r on m.team_id = r.team_id
      and r.season_year = m.season_year
      and m.roster_id = r.roster_id
	inner join temp_active_cnt c on m.error_id = c.error_id
where r.roster_len = 5
union
select c.sub_id, r.player_id4 player_id
from temp_match_roster_max m
	inner join ref_roster r on m.team_id = r.team_id
      and r.season_year = m.season_year
      and m.roster_id = r.roster_id
	inner join temp_active_cnt c on m.error_id = c.error_id
where r.roster_len = 5
union
select c.sub_id, r.player_id5 player_id
from temp_match_roster_max m
	inner join ref_roster r on m.team_id = r.team_id
      and r.season_year = m.season_year
      and m.roster_id = r.roster_id
	inner join temp_active_cnt c on m.error_id = c.error_id
where r.roster_len = 5) a;

create index temp_active_players_sub_idx on temp_active_players(sub_id);
create index temp_active_players_plater_idx on temp_active_players(player_id);

drop table if exists temp_match_roster;
drop table if exists temp_match_roster_max;
drop table if exists temp_errors_match;
drop table if exists temp_full_roster_cnt;
drop table if exists temp_full_roster;
drop table if exists temp_active_errors_cnt;
drop table if exists temp_active_errors;
drop table if exists temp_active_cnt;

/***   Add roster id to action table ***/
-- merge pbp with roster id
drop table if exists temp_roster_cross; 
create table stg.temp_roster_cross as(
select  d.season_year, r1.player_id player_id1
	,r2.player_id player_id2, r3.player_id player_id3, r4.player_id player_id4
    , r5.player_id player_id5 ,a.pbp_id, a.team_id
from temp_active_players r1
	inner join temp_sub_blocks b on r1.sub_id = b.sub_id
    inner join stg.games g on b.match_id = g.match_id
    inner join stg.ref_date d on g.game_date = d.game_date
	inner join temp_active_players r2 on r1.sub_id = r2.sub_id
	inner join temp_active_players r3 on r1.sub_id = r3.sub_id 
	inner join temp_active_players r4 on r1.sub_id = r4.sub_id 
	inner join temp_active_players r5 on r1.sub_id = r5.sub_id 
	inner join stg.action a on b.match_id = a.match_id
		AND b.team_id = a.team_id
        AND b.qtr = a.qtr
        AND b.pbp_id_start <= a.pbp_id
        AND b.pbp_id_end > a.pbp_id
where r1.player_id > r2.player_id
    and r2.player_id > r3.player_id
    and r3.player_id > r4.player_id
    and r4.player_id > r5.player_id);

create index temp_roster_cross_player_idx on temp_roster_cross(player_id1, player_id2, player_id3, player_id4, player_id5,season_year);
create index temp_roster_cross_pbp_idx on temp_roster_cross(pbp_id);

-- merge roster with pbp_id
drop table if exists action_roster;
create table action_roster as(
select r.roster_5_id roster_id, a.pbp_id, a.match_id, a.team_id, a.qtr, a.game_time
	, a.player_id1, a.player_id2, a.player_id3, a.action_id
from temp_roster_cross c
	inner join ref_roster r on r.player_id1 = c.player_id1 and r.player_id2 = c.player_id2
		and r.player_id3 = c.player_id3 and r.player_id4 = c.player_id4 
        and r.player_id5 = c.player_id5 and r.season_year = c.season_year
        and r.team_id = c.team_id
	inner join action a on c.pbp_id = a.pbp_id
where r.roster_len = 5);

create index action_roster_match_idx on action_roster(match_id);
create index action_roster_player_idx on action_roster(player_id1);
create index action_roster_action_idx on action_roster(action_id);
create index action_roster_all_idx on action_roster(match_id,player_id1,action_id);

