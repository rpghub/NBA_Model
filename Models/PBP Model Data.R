### Add opponent roster and set up data for model

library(data.table)
library(Rcpp)
library(RODBC)

conn = odbcConnect("NBADB")
sql1 = "select * from stg.pbp_model"
pbp = as.data.table(sqlQuery(conn,sql1))


# get starting roster for each qtr and add to pbp 
pbp[, rnk := frank(pbp_id), .(match_id, team_id, qtr)]
roster_start <- pbp[rnk == 1,.(opp_roster_id = roster_id, opp_id = team_id
                               , match_id, qtr, rnk)]

pbp[, opp_id := ifelse(team_id == visit_team_id, home_team_id, visit_team_id)]

setkey(roster_start, opp_id, match_id, qtr, rnk)
setkey(pbp, opp_id, match_id, qtr, rnk)
pbp <- roster_start[pbp][order(pbp_id)]

# loop through pbp table and update opp roster
while (nrow(pbp[is.na(opp_roster_id)]) > 0){
  pbp[, opp_roster_id := ifelse(shift(team_id, 1L, type = "lag") == team_id
                                , shift(opp_roster_id, 1L, type = "lag")
                                , shift(roster_id, 1L, type = "lag"))
      , .(match_id, qtr)]
  
  setkey(roster_start, opp_id, match_id, qtr, rnk)
  setkey(pbp, opp_id, match_id, qtr, rnk)
  pbp <- roster_start[pbp][order(pbp_id)]
  
  pbp[!is.na(i.opp_roster_id), opp_roster_id := i.opp_roster_id]
  pbp[, i.opp_roster_id := NULL]
}

# put rosters on home and visit basis
pbp[, home_roster_id := ifelse(team_id == home_team_id
                               , roster_id
                               , opp_roster_id)]

pbp[, visit_roster_id := ifelse(team_id == home_team_id
                                , opp_roster_id
                                , roster_id)]


# collpase pbp data by roster & opp roster and get summary stats
points <- pbp[type1 %in% c("shot", "free throw") & subtype1 == "made"
              , .(pts = ifelse(points1 < 0, points2, points1)
                  , match_id, home_roster_id, visit_roster_id
                  , team_id, home_team_id, visit_team_id, game_date
                  , season_year)
              ][, .(home_pts = ifelse(team_id == home_team_id, pts, 0)
                    , visit_pts = ifelse(team_id == home_team_id, 0, pts)
                    , match_id, home_roster_id, visit_roster_id, game_date
                    , season_year, home_team_id, visit_team_id)
                ][, .(home_pts = as.numeric(sum(home_pts))
                      , visit_pts = as.numeric(sum(visit_pts)))
                  , .(match_id, home_roster_id, visit_roster_id, game_date
                      , season_year, home_team_id, visit_team_id)]

possessions <- pbp[!is.na(type1)
                   , .(shot1 = ifelse(type1 %in% c("shot", "free throw"), 1, 0)
                       , shot2 = ifelse(type2 %in% c("shot", "free throw"), 1, 0)
                       , to1 = ifelse(type1 == "turnover", 1, 0)
                       , to2 = ifelse(type2 == "turnover", 1, 0)
                       , reb1 = ifelse(type1 == "rebound" 
                                       & subtype1 == "offensive"
                                       , 1, 0)
                       , reb2 = ifelse(type2 == "rebound" 
                                       & subtype2 == "offensive"
                                       , 1, 0)
                       , match_id, home_roster_id, visit_roster_id, game_date
                       , season_year, home_team_id, visit_team_id, pbp_id)
                   ][, .(pos = sum(shot1) + sum(shot2) + sum(to1) + sum(to2)
                         - sum(reb1) - sum(reb2)
                         , cnt = .N
                         , pbp_min = min(pbp_id))
                     , .(match_id, home_roster_id, visit_roster_id, game_date
                         , season_year, home_team_id, visit_team_id)]

# combine collapsed summary stats
setkey(points, match_id, home_roster_id, visit_roster_id, game_date
       , season_year, home_team_id, visit_team_id)
setkey(possessions, match_id, home_roster_id, visit_roster_id, game_date
       , season_year, home_team_id, visit_team_id)

pbp_elo <- points[possessions]
pbp_elo[is.na(home_pts), home_pts := 0]
pbp_elo[is.na(visit_pts), visit_pts := 0]

# set up data in format for models
pbp_elo <- pbp_elo[pos > 0, .(match_id, home_roster_id, visit_roster_id
                              , home_team_id, visit_team_id
                              , home_pts, visit_pts, pos, game_date
                              , mov = abs(home_pts - visit_pts)
                              , result = ifelse(home_pts >= visit_pts
                                                , ifelse(home_pts == visit_pts
                                                         , .5, 1)
                                                , 0)
                              , new_season = 0, elo = 1300, elo_start = 1300
                              , opp_elo_start = 1300, opp_elo = 1300
                              , est = .5, error = 0, season_year, pbp_min)]

# add days of rest
rest <- rbind(pbp_elo[, .(home = 1)
                      , .(team_id = home_team_id, game_date
                          , match_id)]
              , pbp_elo[, .(home = 0)
                        , .(team_id = visit_team_id, game_date
                            , match_id)])

rest <- rest[order(team_id, game_date)]
rest[, game_date_prior := shift(game_date, 1L, "lag", fill = 0), .(team_id)]
rest[game_date - game_date_prior == 1
     , rest := 1]
rest[game_date - game_date_prior == 2
     , rest := 2]
rest[game_date - game_date_prior == 3
     , rest := 3]
rest[game_date - game_date_prior > 3
     , rest := 4]

rest <- cbind(rest[order(match_id)
                   ][home == 1
                     , .(match_id, home_team_id = team_id, home_rest = rest)]
              , rest[order(match_id)
                     ][home == 0
                       , .( visit_team_id = team_id, visit_rest = rest)])

setkey(rest, home_team_id, visit_team_id, match_id)
setkey(pbp_elo, home_team_id, visit_team_id, match_id)
pbp_elo <- pbp_elo[rest]

# save model to model directory
setwd("C:/Projects/NBA_Model/Models ")
write.csv(pbp_elo, "pbp_model.csv", row.names = FALSE)
