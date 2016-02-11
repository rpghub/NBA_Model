/***   Table definitions for stg   ***/

CREATE SCHEMA stg;

CREATE TABLE stg.boxscore (
  box_id integer auto_increment primary key,
  match_id integer,
  team varchar(30),
  player varchar(250),
  min_ double,
  fgm_a varchar(10),
  pm3_a varchar(10),
  ftm_a varchar(10),
  oreb int,
  dreb int,
  reb int,
  ast int,
  stl int,
  blk int,
  to_ int,
  pf int,
  pts int
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX match_id_idx ON stg.boxscore (match_id);
ALTER TABLE boxscore ADD UNIQUE INDEX match_id_unique (match_id, team, player); 

CREATE TABLE stg.games (
  match_id integer primary key,
  game_date date DEFAULT NULL,
  home_team varchar(30),
  home_team_score int,
  visit_team varchar(30),
  visit_team_score int
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX game_date_idx ON stg.games(game_date);
CREATE INDEX GAME_HOME_TEAM_IDX ON stg.games(home_team);
CREATE INDEX GAME_VISIT_TEAM_IDX ON stg.games(visit_team);

CREATE TABLE stg.team_search (
  team_search_id integer auto_increment primary key,
  prefix_1 varchar(4),
  prefix_2 varchar(50),
  team varchar(50),
  url varchar(255)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE stg.play_by_play (
  pbp_id integer auto_increment primary key,
  match_id integer,
  game_time datetime,
  qtr integer,
  home_action varchar(250),
  home_team_score integer,
  visit_action varchar(250),
  visit_team_score integer
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX match_id_idx ON stg.play_by_play (match_id);
CREATE INDEX home_action_idx ON stg.play_by_play (home_action);
CREATE INDEX visit_action_idx ON stg.play_by_play (visit_action);
  
CREATE TABLE stg.pbp_working(
  pbp_id integer auto_increment primary key,
  match_id integer,
  game_time datetime,
  qtr integer,
  play_action_id integer,
  home_team_score integer,
  visit_team_score integer
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX match_id_idx ON stg.play_by_play (match_id);

CREATE TABLE stg.ref_teams (
  ref_team_id integer auto_increment primary key,
  team_id integer,
  season_year integer,
  team_name varchar(60),
  city_name varchar(40),
  isDefault integer
)ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX ref_teams_default_idx ON stg.ref_teams(isDefault);
CREATE INDEX ref_teams_team_name_idx ON stg.ref_teams(team_name);
CREATE INDEX ref_teams_team_id_idx ON stg.ref_teams(team_id);
 
CREATE TABLE stg.ref_date (
  game_date date primary key,
  game_year integer,
  game_month integer,
  game_day integer,
  season_year integer
)ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE stg.ref_action (
  action_id integer auto_increment primary key
  ,action_grp_id int
  ,action_txt varchar(250)
  ,type1 varchar(30)
  ,subtype1 varchar(30)
  ,ft1 integer default -1
  ,points1 integer default -1
  ,type2 varchar(30)
  ,subtype2 varchar(30)
  ,ft2 integer default -1
  ,points2 integer default -1
  ,type3 varchar(30)
  ,subtype3 varchar(30)
  ,ft3 integer default -1
  ,points3 integer default -1
  ,isDefault integer
  ,FLAG varchar(25)
)ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX REF_ACTION_ACTION_IDX ON stg.ref_action(action_txt);
CREATE INDEX REF_ACTION_ACTION_GRP_IDX ON stg.ref_action(action_grp_id);
create index ref_action_type1_idx on ref_action(type1);
create index ref_action_type2_idx on ref_action(type2);



CREATE TABLE stg.cross_team (
  cross_team_id integer auto_increment primary key
  ,team_odd_id int
  ,team_id int
  ,team_odd_name varchar(50)
)ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX CROSS_TEAM_TEAM_ID_IDX ON stg.cross_team(team_id);
CREATE INDEX CROSS_TEAM_TEAM_ODD_ID_IDX ON stg.cross_team(team_odd_id);

CREATE TABLE stg.game_odds (
  match_id int primary key
  ,team_id int
  ,opp_team_id int 
  ,game_date date
  ,season_year int
  ,home int
  ,pts int
  ,opp_pts int
  ,ot int
  ,ou varchar(1)
  ,ou_pts decimal(4,1)
  ,line decimal(3,1)
  ,line_wl varchar(1)
)ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE INDEX GAME_ODDS_TEAM_IDX ON stg.game_odds(team_id);
CREATE INDEX GAME_ODDS_GAME_IDX ON stg.game_odds(match_id);


/*CREATE VIEWS OF DATA TO QUERY*/

CREATE VIEW stg.play_by_play_missing AS
	SELECT g.* 
    FROM stg.games g 
		LEFT JOIN stg.play_by_play p ON p.match_id = g.match_id
	WHERE p.match_id IS NULL;
    
    
CREATE VIEW stg.games_missing AS
	SELECT g.* 
    FROM stg.games g 
		LEFT JOIN stg.boxscore sg ON sg.match_id = g.match_id
	WHERE sg.match_id IS NULL;


select * from games_missing