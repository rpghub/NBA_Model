### xgboost individual player poisson model

library(data.table)
library(xgboost)
library(Matrix)
library(ggplot2)

setwd("C:\\Projects\\NBA_Model\\Models")
pbp_fit <- fread("pbp_model.csv")
player <- fread("player.csv")
pbp_fit[, game_date := as.Date(game_date, "%Y-%m-%d")]
pbp_fit <- pbp_fit[season_year %in% c(2007)]

# add player indicators based on roster
setkey(pbp_fit, home_roster_id, home_team_id)
setkey(player, roster_id, team_id)

pbp_xgb <- player[, .(roster_id, team_id, player_id1, player_id2, player_id3
                      , player_id4, player_id5)
                  ][pbp_fit]

setnames(pbp_xgb, c("roster_id", "team_id", "player_id1", "player_id2"
                    , "player_id3", "player_id4", "player_id5")
         , c("home_roster_id", "home_team_id", "home_player_id1"
             , "home_player_id2", "home_player_id3", "home_player_id4"
             , "home_player_id5"))

setkey(pbp_xgb, visit_roster_id, visit_team_id)
setkey(player, roster_id, team_id)

pbp_xgb <- player[, .(roster_id, team_id, player_id1, player_id2, player_id3
                      , player_id4, player_id5)
                  ][pbp_xgb]

setnames(pbp_xgb, c("roster_id", "team_id", "player_id1", "player_id2"
                    , "player_id3", "player_id4", "player_id5")
         , c("visit_roster_id", "visit_team_id", "visit_player_id1"
             , "visit_player_id2", "visit_player_id3", "visit_player_id4"
             , "visit_player_id5"))


# melt, add offense and defense dummy vars and collapse back to roster level
pbp_xgb <- melt.data.table(pbp_xgb
                           , c("match_id", "game_date", "home_team_id"
                               , "home_roster_id", "visit_team_id"
                               , "visit_roster_id", "home_rest"
                               , "visit_rest", "pos", "season_year"
                               , "home_pts", "visit_pts")
                           , measure=patterns("home_player_id"
                                              , "visit_player_id")
                           , value.name = c("home_player", "visit_player"))

pbp_xgb <- rbind(pbp_xgb[, .(match_id, game_date, team_id = home_team_id
                             , roster_id = home_roster_id
                             , opp_team_id = visit_team_id
                             , opp_roster_id = visit_roster_id
                             , rest = home_rest
                             , opp_rest = visit_rest
                             , season_year
                             , pts = home_pts, opp_pts = visit_pts
                             , player = home_player
                             , opp_player = visit_player
                             , home = 1
                             , pos)]
                 , pbp_xgb[, .(match_id, game_date, team_id = visit_team_id
                               , roster_id = visit_roster_id
                               , opp_team_id = home_team_id
                               , opp_roster_id = home_roster_id
                               , rest = visit_rest
                               , opp_rest = home_rest
                               , season_year
                               , pts = visit_pts, opp_pts = home_pts
                               , player = visit_player
                               , opp_player = home_player
                               , home = 0
                               , pos)])
                 
# add home and visit player dummy vars
player_list = unique(c(pbp_xgb$player, pbp_xgb$opp_player))

p_list_names = paste(rep("p", length(player_list)), player_list, sep = '')
pbp_xgb[, (p_list_names) := lapply(player_list, function(x) player == x)]

p <- Matrix(as.matrix(pbp_xgb[, lapply(.SD, max)
                               , .(match_id, game_date, team_id, roster_id
                                   , opp_team_id, opp_roster_id, rest
                                   , opp_rest, season_year, pts, opp_pts
                                   , home, pos)
                              ][,16:ncol(pbp_xgb), with = FALSE])
             , sparse = TRUE)

pbp_xgb = pbp_xgb[,1:15, with = FALSE]

p_list_names = paste(rep("op", length(player_list)), player_list, sep = '')
pbp_xgb[, (p_list_names) := lapply(player_list, function(x) opp_player == x)]

op <- Matrix(as.matrix(pbp_xgb[, lapply(.SD, max)
                               , .(match_id, game_date, team_id, roster_id
                                   , opp_team_id, opp_roster_id, rest
                                   , opp_rest, season_year, pts, opp_pts
                                   , home, pos)
                               ][,16:ncol(pbp_xgb), with = FALSE])
            , sparse = TRUE)

pbp_xgb = pbp_xgb[,1:15, with = FALSE]

rm(player_list, p_list_names)

# add home and visit team dummy vars
team_list = unique(c(pbp_xgb$team_id, pbp_xgb$opp_team_id))

t_list_names = paste(rep("t", length(team_list)), team_list, sep = '')
pbp_xgb[, (t_list_names) := lapply(team_list, function(x) team_id == x)]

t_list_names = paste(rep("ot", length(team_list)), team_list, sep = '')
pbp_xgb[, (t_list_names) := lapply(team_list, function(x) opp_team_id == x)]

rm(team_list, t_list_names)

# collapse back to roster level
pbp_xgb <- pbp_xgb[, lapply(.SD, max)
                   , .(match_id, game_date, team_id
                       , roster_id, opp_team_id
                       , opp_roster_id, rest
                       , opp_rest, season_year
                       , pts, opp_pts
                       , home, pos)]

tr <- sparse.model.matrix(~ -1 + as.factor(roster_id) + as.factor(opp_roster_id)
                          , data = pbp_xgb)

# create sparse matrixes to use for xgboost
max_date <- summary(unique(pbp_xgb$game_date))[5]

train <- pbp_xgb$game_date <= max_date
test <- pbp_xgb$game_date > max_date


pbp_train <- pbp_xgb[game_date <= max_date, 12:ncol(pbp_xgb), with = FALSE]
pbp_train <- xgb.DMatrix(data = cBind(Matrix(as.matrix(pbp_train)
                                             , sparse = TRUE)
                                      , p[train,], op[train,]) #, tr[train,])
                         , label = pbp_xgb[game_date <= max_date]$pts)

pbp_test <- pbp_xgb[game_date > max_date, 12:ncol(pbp_xgb), with = FALSE]
pbp_test <- xgb.DMatrix(data = cBind(Matrix(as.matrix(pbp_test)
                                            , sparse = TRUE)
                                     , p[test,], op[test,]) #, tr[test,])
                         , label = pbp_xgb[game_date > max_date]$pts)


watchlist = list(test = pbp_test, train = pbp_train)

bst <- xgb.train(data = pbp_train, max.depth=1, nround=1000
                 , print.every.n = 50
                 , early.stop.round = 5
                 , maximize = FALSE
                 , watchlist=watchlist
                 , objective = "count:poisson")


preds <- predict(bst, pbp_test)

cbind(pbp_xgb[game_date > max_date], preds
      )[, .(home_preds = sum(ifelse(home == 1, preds, 0))
            , home_pts = sum(ifelse(home == 1, pts, 0))
            , visit_preds = sum(ifelse(home == 0, preds, 0))
            , visit_pts = sum(ifelse(home == 0, pts, 0)))
        , .(match_id)
        ][home_pts != visit_pts
          , .(sum(ifelse((home_pts > visit_pts & home_preds > visit_preds) |
                          (home_pts < visit_pts & home_preds < visit_preds)
                        , 1, 0)) / .N
              , .N)]



# check model fit
pred_indv <- cbind(pbp_xgb[game_date > max_date
                           , .(match_id, roster_id, team_id
                           , home, pts, pos)]
                   , preds)

pred_indv[, pos_bin := cut(pos, c(0, 5, 10, 25, Inf))]

ggplot(pred_indv, aes(x = (pts - preds)^2/preds, y = ..density..)) + 
  geom_histogram(binwidth = .1) +
  facet_wrap(~pos_bin) +
  xlim(0,5)

pred_indv[, .(od = mean((pts - preds)^2 / preds), cnt = .N), .(pos_bin)][order(pos_bin)]


pred_indv_sim <- pred_indv[, .(preds = rpois(1000, preds)
                               , iter = seq_len(1000))
                           , .(match_id, roster_id, team_id, home, pts, pos)]

pred_indv_sim[, .(preds = sum(preds)
                  , pts = sum(pts))
              , .(iter, match_id, team_id, home)]


pred_indv_sim[, .(home_preds = sum(ifelse(home == 1, preds, 0))
                  , home_pts = sum(ifelse(home == 1, pts, 0))
                  , visit_preds = sum(ifelse(home == 0, preds, 0))
                  , visit_pts = sum(ifelse(home == 0, pts, 0)))
              , .(match_id, iter)
              ][home_pts != visit_pts
                , .(pcnt = sum(home_preds > visit_preds) / .N)
                , .(match_id, home_pts, visit_pts)
                ][, .(act = sum(home_pts > visit_pts) / .N
                      , cnt = .N)
                  , .(bin = cut(pcnt, seq(0, 1, .1)))
                  ][order(bin)]
