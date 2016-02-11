/***   Append scrape results table to new table (games)  ***/

USE stg;
INSERT INTO games(match_id,game_date,home_team,home_team_score
	,visit_team, visit_team_score)
SELECT match_id
	,date
    ,home_team
    ,home_team_score
    ,visit_team
    ,visit_team_score
FROM stggames;


/***   Load ref_teams   ***/

USE stg;
LOAD DATA INFILE 'teams.csv' INTO TABLE ref_teams
  FIELDS TERMINATED BY ',' ENCLOSED BY '"'
  LINES TERMINATED BY '\r\n'
  IGNORE 1 LINES;

/***   Load ref_action   ***/

USE stg;
LOAD DATA INFILE 'actions.csv' INTO TABLE ref_action
  FIELDS TERMINATED BY ',' ENCLOSED BY '"'
  LINES TERMINATED BY '\r\n'
  IGNORE 1 LINES;

/***   Append scrape results table to new table (play_by_play)  ***/

USE stg;
INSERT INTO play_by_play(match_id,
  game_time,
  qtr,
  home_action,
  home_team_score,
  visit_action,
  visit_team_score)
SELECT match_id,
  game_time,
  qtr,
  home_action,
  home_team_score,
  visit_action,
  visit_team_score
FROM stgplay_by_play;

-- correct pbp_id so that it is in chronological order (should fix this)
drop table if exists pbp_fix;
create table pbp_fix(
pbp_id_new integer auto_increment primary key,
pbp_id integer);
 
insert into pbp_fix(pbp_id)
select pbp_id
from stg.play_by_play
order by match_id, qtr, game_time desc;

update play_by_play p inner join pbp_fix f on p.pbp_id = f.pbp_id
set p.pbp_id = f.pbp_id_new;
 
update action a inner join pbp_fix on a.pbp_id = f.pbp_id
set a.pbp_id = f.pbp_id_new;

drop table pbp_fix;

/***   Append scrape results table to new table (boxscore)   ***/

INSERT IGNORE INTO stg.boxscore(match_id,team,player,min_,fgm_a,pm3_a,ftm_a,oreb
,dreb,reb,ast,stl,blk,to_,pf,pts)
SELECT bs.id AS match_id,
    bs.team AS team,
    bs.player AS player,
    bs.`MIN` AS min_,
    bs.`FGM-A` AS fgm_a,
    bs.`3PM-A` AS pm3_a,
    bs.`FTM-A` AS ftm_a,
    bs.OREB AS oreb,
    bs.DREB AS dreb,
    bs.REB AS reb,
    bs.AST AS ast,
    bs.STL AS stl,
    bs.BLK AS blk,
    bs.`TO` AS to_,
    bs.PF AS pf,
    CAST(bs.PTS AS UNSIGNED INT) AS pts
FROM stg.stgboxscore bs;

/***   Append scrape results table to new table (team_search)  ***/

USE stg;
INSERT INTO team_search(prefix_1, prefix_2, team, url)
SELECT prefix_1,
	prefix_2,
    team,
    url
FROM stgteam;

/***   Append scrape results table to new table (game_odds)  ***/

-- relate team_odd to ref_teams
insert into cross_team(team_odd_id, team_id, team_odd_name)
select distinct o.team_odd_id, r.team_id, o.team 
from stgteam_odds o 
  inner join ref_teams r on o.team = r.city_name
where r.season_year = 2014;

-- crosswalk odds info to team_id and match_id
drop table if exists temp_odds_result;
create table temp_odds_result as(
select t1.team_id team_id, t2.team_id opp_team_id , cast(home as unsigned) home
  , cast(pts as decimal(3,0)) pts
  , cast(opp_pts as decimal(3,0)) opp_pts
  , cast(ot as unsigned) ot
  , ou, cast(ou_pts as decimal(4,1)) ou_pts
  , line_wl,  cast(case when line = 'PK' then 0 else line end as decimal(3,1)) line
  , str_to_date(o.game_date, '%m/%d/%Y') game_date
from stgteam_odds_result o 
  inner join cross_team t1 on o.team_odd_id = t1.team_odd_id 
  inner join cross_team t2 on o.opp_odd_id = t2.team_odd_id); 

drop table if exists temp_games;
create table temp_games as(
select g.match_id, g.game_date, r1.team_id, r2.team_id opp_team_id
	, d.season_year
from games g 
	inner join ref_date d on g.game_date = d.game_date
	inner join ref_teams r1 on g.home_team = r1.team_name 
	  and d.season_year = r1.season_year
	inner join ref_teams r2 on g.visit_team = r2.team_name
	  and d.season_year = r2.season_year);

create index temp_games_all_idx on temp_games(game_date, team_id, opp_team_id);
create index temp_odds_result_all_idx on temp_odds_result(game_date, team_id, opp_team_id);

insert into game_odds
select distinct g.match_id, o.team_id, o.opp_team_id, g.game_date, g.season_year
  , o.home, o.pts, o.opp_pts, o.ot, o.ou, o.ou_pts, o.line, o.line_wl
from temp_odds_result o
  inner join temp_games g on o.game_date = g.game_date
    and o.team_id = g.team_id and o.opp_team_id = g.opp_team_id;

drop table temp_games;
drop table temp_odds_result;
