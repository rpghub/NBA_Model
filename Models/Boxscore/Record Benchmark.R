### boxscore record benchmark

library(data.table)
library(ggplot2)
library(zoo)

setwd("C:\\Projects\\NBA_Model\\Models")
box <- fread("boxscore.csv")
box_elo <- fread("boxscore elo.csv")
box[, game_date := as.Date(game_date, "%Y-%m-%d")]

# get game totals
gm <- box[, .(pts = sum(pts)
              , home_id = as.integer(max(ifelse(home == 1, team_id
                                                , opp_team_id)))
              , visit_id = as.integer(max(ifelse(home == 1, opp_team_id
                                                 , team_id))))
          , .(match_id, team_id, home, game_date, season_year)]

# add opponent points and game results
gm[, max_pts := max(pts), .(match_id)]
gm[, rslt := pts == max_pts]


# add elo ratings
setkey(box_elo, match_id, team_id)
setkey(gm, match_id, team_id)
gm <- gm[box_elo]

# get cumulative record
setkey(gm, team_id, season_year, game_date)
gm[, cum_win := cumsum(rslt), .(team_id, season_year)]
gm[, cum_loss := cumsum(1 - rslt), .(team_id, season_year)]
gm[, rcd := (cum_win - rslt) / (cum_win + cum_loss - 1)]
gm[is.na(rcd), rcd := .5]

# reshape to have one row per game
gm <- dcast.data.table(gm, match_id + season_year + game_date + home_id + 
                         visit_id ~ home
                       , value.var = list("rcd", "pts", "elo_start"
                                          , "elo_end"))
gm[, rslt := (rcd_0 == rcd_1 & pts_0 > pts_1) | 
     sign(rcd_0 - rcd_1) == sign(pts_0 - pts_1)]

gm[, rslt_elo := (elo_start_0 == elo_start_1 & pts_0 > pts_1) | 
     sign(elo_start_0 - elo_start_1) == sign(pts_0 - pts_1)]


s_date = '2014-02-15'
e_date = '2014-04-20'
# cumulative record accuracy
gm[game_date >= s_date & game_date < e_date
   , .(pcnt = sum(rslt) / .N
       , pcnt_elo = sum(rslt_elo) / .N)
   , .(season_year)
   ][order(season_year)]

# fixed time record accuacy
gm[, rcd_fixed_1 := NULL]
gm[, rcd_fixed_0 := NULL]
gm[, rslt_fix := NULL]

min_game_date <- box[game_date >= s_date
                     , .(min_date = min(game_date))
                     , .(team_id)]
setkey(min_game_date, team_id, min_date)
setkey(gm, home_id, game_date)
rcd_home <- gm[min_game_date, .(team_id = home_id, rcd_fixed = rcd_1)
               , nomatch = 0]
setkey(gm, visit_id, game_date)
rcd_visit <- gm[min_game_date, .(team_id = visit_id, rcd_fixed = rcd_0)
                , nomatch = 0]
rcd_fix <- rbind(rcd_home, rcd_visit)

setkey(gm, home_id)
gm <- gm[rcd_fix]
setnames(gm, "rcd_fixed", "rcd_fixed_1" )
setkey(gm, visit_id)
gm <- gm[rcd_fix]
setnames(gm, "rcd_fixed", "rcd_fixed_0" )
rm(rcd_visit, rcd_home, min_game_date, rcd_fix)


gm[, rslt_fix := (rcd_fixed_0 == rcd_fixed_1 & pts_0 > pts_1) | 
     sign(rcd_fixed_0 - rcd_fixed_1) == sign(pts_0 - pts_1)]

gm[game_date >= s_date & game_date < e_date
   , .(pcnt = sum(rslt_fix) / .N), .(season_year)
   ][order(season_year)]


# graph cumulative accuracy of record
rslt_cum <- gm[, .(rslt = sum(rslt), rslt_elo = sum(rslt_elo), cnt = .N)
               , .(game_date, season_year)
               ][order(season_year, game_date)
                 ][, .(game_date, rslt = cumsum(rslt)
                       , rslt_elo = cumsum(rslt_elo)
                       , cnt = cumsum(cnt))
                   , .(season_year)
                   ][, .(season_year, game_date, pcnt = rslt / cnt
                         , rslt, pcnt_elo = rslt_elo / cnt
                         , rslt_elo, cnt)]

ggplot(rslt_cum[season_year >= 2012], aes(x = cnt)) + 
  geom_point(aes(y = pcnt), color = "salmon") +
  geom_point(aes(y = pcnt_elo), color = "dodgerblue4") + 
  facet_wrap(~season_year)

# graph rolling accuracy of record
n = 30
rslt_roll <- gm[, .(rslt = sum(rslt), rslt_elo = sum(rslt_elo), cnt = .N)
               , .(game_date, season_year)
               ][order(season_year, game_date)
                 ][, .(game_date, rslt = rollapply(rslt, n, sum, fill = NA
                                                   , align = 'right')
                       , rslt_elo = rollapply(rslt_elo, n, sum, fill = NA
                                              , align = 'right')
                       , cnt = rollapply(cnt, n, sum, fill = NA
                                         , align = 'right')
                       , cnt_cum = cumsum(cnt))
                   , .(season_year)
                   ][, .(season_year, game_date, pcnt = rslt / cnt
                         , rslt, pcnt_elo = rslt_elo / cnt
                         , rslt_elo, cnt, cnt_cum)]

ggplot(rslt_roll[!(month(game_date) %in% c(5,6))], aes(x = cnt_cum)) + 
  geom_point(aes(y = pcnt), color = "salmon") +
  geom_point(aes(y = pcnt_elo), color = "dodgerblue4") + 
  facet_wrap(~season_year)


ggplot(rslt_roll[!(month(game_date) %in% c(5,6))]
       , aes(x = cnt_cum, y = pcnt_elo - pcnt)) + 
  geom_hline(yintercept = 0) +
  geom_line() +
  facet_wrap(~season_year)


