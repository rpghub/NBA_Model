/***   Append scrape results table to new table (games)  ***/

USE stg;
INSERT IGNORE INTO games(match_id,game_date,home_team,home_team_score
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
LOAD DATA INFILE 'C:/Projects/NBA_Model/DB/teams.csv' INTO TABLE ref_teams
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

/*** manual corrections to ref_player   ***/
insert into stgbox_player values(str_to_date('1990-01-06', '%Y-%m-%d'), 'University of Cincinnati', -1, -1, NULL, -1, 1, 76, 'Sean Kilpatrick', 'S. Kilpatrick', 'http://espn.go.com/nba/player/_/id/2488689', 210);
insert into stgbox_player values(str_to_date('1977-03-09', '%Y-%m-%d'), NULL, -1, -1, NULL, -1, 1, 84, 'Boniface Dong', 'B. Napos;Do', 'http://espn.go.com/nba/player/_/id/2874/boniface-naposdong', 198);

drop table if exists temp_fix_players ;
create table temp_fix_players as( 
select b.player
from stgbox_player b
  left join ref_player p on b.player = p.player
where p.player is null and b.player_lname is not null);

insert into ref_player(player_id, player, isDefault, cnt)
select distinct p.player_id, f.player, 0, 0
from ref_player p
  inner join temp_fix_players f on f.player like concat('%', p.player, '%');

select distinct p.player_id, f.player, 0, 0, p.player
from ref_player p
  inner join temp_fix_players f 
  on p.player like concat('%', right(f.player, length(f.player) - locate(' ', f.player)) , '%');

insert into ref_player(player_id, player, isDefault, cnt) values(794, 'JJ Hickson', 0, 0);

set @player_id = (select max(player_id) from ref_player) + 1;
insert into ref_player(player_id, player, isDefault, cnt)
select @player_id := @player_id + 1 , f.player, 1, 0
from temp_fix_players f;

select count(*) cnt, player 
from ref_player 
group by player 
having cnt > 1;

select count(*) cnt, player_id 
from ref_player 
where isDefault = 1 
group by player_id 
having cnt > 1;

drop table if exists temp_fix_players ;

/***   Append scrape results table to new table (player)   ***/
create table stgboxscore_backup as(select * from stgboxscore);
create table stgbox_player_backup as(select * from stgbox_player);


alter table stgboxscore change url url varchar(70);
alter table stgbox_player change url url varchar(70);
alter table stgbox_player change player player varchar(70);

create index url_idx on stgboxscore(url);
create index url_idx on stgbox_player(url);
create index player_idx on stgbox_player(player);

insert into player
select distinct p.player_id, str_to_date(b.bdate, '%Y-%m-%d') bdate
  , b.college, b.draft_num, b.draft_rnd, b.draft_team
  , b.draft_year, b.exp, b.height, b.player, b.player_lname
  , b.url, b.weight
from stgboxscore bs
  inner join stgbox_player b on bs.url = b.url
  inner join games g on bs.id = g.match_id
  inner join ref_date d on g.game_date = d.game_date
  inner join ref_teams t on bs.team = t.team_name and d.season_year = t.season_year
  inner join ref_player p on b.player = p.player and t.team_id = p.team_id and p.season_year = d.season_year;

  
/***   Append scrape results table to new table (boxscore)   ***/
INSERT INTO boxscore(match_id, team,team_id, player, player_id, position, starter, min_, fgm
, fga, pm3, pm3_a, ftm, fta, oreb
, dreb, reb, ast, stl, blk, tov, pf, pts, pm)
select distinct bs.id match_id, bs.team, t.team_id, bs.player, p.player_id
   , bs.position
   , bs.starter
   , bs.MIN
   , left(bs.FG, locate('-', bs.FG) - 1) fgm
   , right(bs.FG, length(bs.FG) - locate('-', bs.FG)) fgm_a
   , left(bs.3PT, locate('-', bs.3PT) - 1) pm3
   , right(bs.3PT, length(bs.3PT) - locate('-', bs.3PT)) pm3_a
   , left(bs.FT, locate('-', bs.FT) - 1) ftm
   , right(bs.FT, length(bs.FT) - locate('-', bs.FT)) ftm_a
   , bs.oreb, bs.dreb, bs.reb, bs.ast, bs.stl, bs.blk, bs.to
   , bs.pf, bs.pts
   , case when bs.`+/-` = '--' then -1 else bs.`+/-` end pm
from stgboxscore bs
  inner join games g on bs.id = g.match_id
  inner join ref_date d on g.game_date = d.game_date
  inner join ref_teams t on d.season_year = t.season_year and t.team_name = bs.team
  left join player p on bs.url = p.url
where bs.MIN != '--' and bs.min is not null 

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
