/***   Validations   ***/

-- match points from pbp against boxscore
drop table if exists check_points;
create table check_points as(
select match_id, a.player_id, sum(a.points) pts 
from (
select p.player
	,r.match_id
	,r.player_id1 player_id
	,a.points1 points
    ,a.type1 type
    ,a.subtype1 subtype
from action_roster r
	inner join ref_player p on r.player_id1 = p.player_id
    inner join ref_action a on r.action_id = a.action_id
	and a.type1 in('shot','free throw') -- and subtype1 = 'made' 
	and p.isDefault = 1
union all
select p.player
	,r.player_id2 player_id
	,r.match_id
    ,a.points2
    ,a.type2
    ,a.subtype2
from action_roster r
	inner join ref_player p on r.player_id2 = p.player_id
	inner join ref_action a on r.action_id = a.action_id
	and a.type2 in('shot','free throw') -- and subtype1 = 'made' 
	and p.isDefault = 1
) a
where subtype = 'made'
group by a.player, a.match_id
);

create index check_points_all on check_points(match_id,player_id);

drop table if exists bad_points;
create table bad_points as(
select b.player
  ,left(fgm_a,locate('-',fgm_a)-1)*2 + left(pm3_a,locate('-',pm3_a)-1) + left(ftm_a,locate('-',ftm_a)-1) as pts_box
  ,c.pts
  ,c.player_id, c.match_id
  ,d.season_year
from boxscore b
  inner join ref_player	p on b.player = p.player
  inner join check_points c on b.match_id = c.match_id and p.player_id = c.player_id
  inner join games g on b.match_id = g.match_id
  inner join ref_date d on g.game_date = d.game_date
  inner join (select count(distinct qtr) cnt, match_id from action_roster group by match_id) fg on fg.match_id = b.match_id
where fg.cnt = 4);
-- having pts_box != pts);

create index bad_points_all on bad_points(match_id,player_id);

-- player level basis
select a.season_year, sum(a.pts_box = a.pts) / count(*) pcnt_correct
  , count(*) cnt
  , sum(a.pts_box != a.pts) cnt_bad
from (
select b.match_id, b.season_year, b.player, b.player_id
  , sum(b.pts_box) pts_box, sum(b.pts) pts
from bad_points b
  inner join game_odds o on b.match_id = o.match_id
where o.ot = 0
group by b.match_id, b.season_year, b.player, b.player_id) a
group by season_year;

-- game level basis
select a.season_year, sum(a.pts_box = a.pts) / count(*) pcnt_correct
  , count(*) games
  , sum(a.pts_box != a.pts) games_bad
from (
select b.match_id, b.season_year
  , sum(b.pts_box) pts_box, sum(b.pts) pts
from bad_points b
  inner join game_odds o on b.match_id = o.match_id
where o.ot = 0 
group by b.match_id, b.season_year) a
group by season_year;


drop table if exists bad_actions;
create table bad_actions as(
select distinct t.action 
from temp_action_full t
  left join ref_action a on t.action = a.action_txt
where a.action_id is null);

