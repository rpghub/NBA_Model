/***   create views to be used by models   ***/

drop view if exists pbp_model;
create view pbp_model as(
  select a.roster_id, a.pbp_id, a.match_id, g.game_date, d.season_year, a.team_id, a.qtr, a.game_time
    , a.player_id1, a.player_id2, a.player_id3, a.action_id
    , r.type1, r.subtype1, r.ft1, r.points1, r.type2, r.subtype2
    , r.ft2, r.points2, r.type3, r.subtype3, r.ft3, r.points3
    , h.team_id home_team_id, v.team_id visit_team_id
  from action_roster a 
    inner join ref_action r on a.action_id = r.action_id
    inner join games g on a.match_id = g.match_id
    inner join ref_date d on g.game_date = d.game_date
	inner join ref_teams h on g.home_team = h.team_name and h.season_year = d.season_year
    inner join ref_teams v on g.visit_team = v.team_name and v.season_year = d.season_year
  where d.season_year in(2003,2004,2005,2006,2007)
  );

drop view if exists roster_players;
create view roster_players as(
  select r.roster_id, r.team_id, t.team_name, r.player_id1, r.player_id2
    , r.player_id3, r.player_id4, r.player_id5
    , p1.player player1
	, p2.player player2, p3.player player3, p4.player player4
    , p5.player player5
  from ref_roster r 
    inner join ref_teams t ON r.team_id = t.team_id and r.season_year = t.season_year
    inner join ref_player p1 ON r.player_id1 = p1.player_id
    inner join ref_player p2 ON r.player_id2 = p2.player_id
    inner join ref_player p3 ON r.player_id3 = p3.player_id
    inner join ref_player p4 ON r.player_id4 = p4.player_id
    inner join ref_player p5 ON r.player_id5 = p5.player_id
  where r.roster_len = 5 and r.season_year in(2003,2004,2005,2006,2007)
    and p1.isDefault = 1 and p2.isDefault = 1 and p3.isDefault = 1
    and p4.isDefault = 1 and p5.isDefault = 1 and t.isDefault = 1);  
    

