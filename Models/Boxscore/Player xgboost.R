### xgboost individual player poisson model

library(data.table)
library(xgboost)
library(Matrix)

setwd("C:\\Projects\\NBA_Model\\Models")
box <- fread("boxscore.csv")
box[, game_date := as.Date(game_date, "%Y-%m-%d")]
box[, bdate := as.Date(bdate, "%Y-%m-%d")]


# reshape wide with player dummy vars
plr <- dcast.data.table(box[minutes > 0]
                        , match_id + team_id ~ player_id
                        , fun.aggregate = length
                        , value.var = "minutes")

colnames(plr)[3:ncol(plr)] <- paste("o_", colnames(plr), sep = '')[3:ncol(plr)]

# cluster four factors
ff <- box[, .(ftr = sum(fta) / sum(pos)
              , fgr = sum(pts) / sum(fga)
              , stl = sum(stl) / sum(pos)
              , oreb = sum(oreb) / sum(pos))
          , .(team_id, season_year)]

clust <- kmeans(ff[, .(ftr, fgr, stl, oreb)], 3)
clust <- data.table(team_id = ff$team_id, season_year = ff$season_year
                    , clust = clust$cluster)
clust <- dcast.data.table(clust, team_id + season_year ~ clust, fun = length)
setnames(clust, c("team_id", "season_year", "c1", "c2", "c3"))

# reshape team dummy vars
tm <- dcast.data.table(unique(box[minutes > 0, .(match_id, home, team_id)])
                        , match_id + home ~ team_id
                        , fun.aggregate = length
                        , value.var = "team_id")

colnames(tm)[3:ncol(tm)] <- paste("t_o_", colnames(tm), sep = '')[3:ncol(tm)]

# reshape rest dummy vars
rst <- dcast.data.table(unique(box[, .(match_id, team_id, rest)])
                        , match_id + team_id ~ rest
                        , fun.aggregate = length
                        , value.var = 'rest')
colnames(rst)[3:ncol(rst)] <- paste("rst_", colnames(rst)[3:ncol(rst)], sep = '')

# get team match aggregates to join with player and team dummy vars
tots <- box[, .(pts = sum(pts), pos = mean(pos), home = mean(home)
                , rest = mean(rest), height = weighted.mean(height, minutes
                                                            , na.rm = TRUE)
                , weight = weighted.mean(weight, minutes, na.rm = TRUE)
                , age = weighted.mean(as.numeric(game_date - bdate)/360
                                      , minutes, na.rm = TRUE))
            , .(match_id, team_id, opp_team_id, game_date, season_year)]


tots <- cbind(id = seq_len(nrow(tots)), tots)

setkey(plr, match_id, team_id)
setkey(tots, match_id, team_id)
mdl <- tots[plr]

setkey(mdl, match_id, home)
setkey(tm, match_id, home)
mdl <- mdl[tm]

# merge players back in for defense
colnames(plr)[3:ncol(plr)] <- paste("d_", colnames(plr), sep = '')[3:ncol(plr)]
setkey(plr, match_id, team_id)
setkey(mdl, match_id, opp_team_id)
mdl <- mdl[plr][order(id)]

#add season dummy var
yrs <- unique(mdl$season_year)
for (i in 1:length(yrs) )
  mdl[, paste('y_', yrs[i], sep = '') := 1 *(yrs[i] == season_year)]

# merge team back in for opp
tm[, home := ifelse(home == 1, 0, 1)]
colnames(tm)[3:ncol(tm)] <- paste("t_d_", colnames(tm), sep = '')[3:ncol(tm)]
setkey(mdl, match_id, home)
setkey(tm, match_id, home)
mdl <- mdl[tm][order(id)]
rm(plr, tots, tm)

# merge in clusters
setkey(clust, season_year, team_id)
setkey(mdl, season_year, team_id)
mdl <- mdl[clust]
setnames(mdl, c('c1', 'c2', 'c3'), c('o_c1', 'o_c2', 'o_c3'))

setkey(mdl, season_year, opp_team_id)
mdl <- mdl[clust][order(id)]
setnames(mdl, c('c1', 'c2', 'c3'), c('d_c1', 'd_c2', 'd_c3'))
rm(clust)

# merge in rest dummy vars
setkey(rst, match_id, team_id)
setkey(mdl, match_id, team_id)
mdl <- mdl[rst]
setnames(mdl, c('rst_0', 'rst_1', 'rst_2', 'rst_3', 'rst_4')
         , c('o_rst_0', 'o_rst_1', 'o_rst_2', 'o_rst_3', 'o_rst_4'))

setkey(mdl, match_id, opp_team_id)
mdl <- mdl[rst][order(id)]
setnames(mdl, c('rst_0', 'rst_1', 'rst_2', 'rst_3', 'rst_4')
         , c('d_rst_0', 'd_rst_1', 'd_rst_2', 'd_rst_3', 'd_rst_4'))

# add cumulative rcd
setkey(gm, match_id)
setkey(mdl, match_id)
mdl <- mdl[gm[, .(match_id, rcd_0, rcd_1)]]
mdl[, rcd_team := ifelse(home == 1, rcd_1, rcd_0)]
mdl[, rcd_opp := ifelse(home == 1, rcd_0, rcd_1)]
mdl[, rcd_0 := NULL]
mdl[, rcd_1 := NULL]
setkey(mdl, id)

# create matrix for xgboost
mat <- as.matrix(cbind(1, mdl[,8:ncol(mdl), with = FALSE]))
mat <- Matrix(mat, sparse = TRUE)

# define test and train sets
train <- mdl[game_date > '2013-10-01' & game_date < '2014-02-15' ]$id
test <- mdl[game_date >= '2014-02-15' & game_date < '2014-04-20']$id
#train <- mdl[season_year %in% c(2007, 2006, 2005)]$id
#test <- mdl[season_year %in% c(2008)]$id

dtrain <- xgb.DMatrix(data = mat[train,], label = mdl$pts[train])
dtest <- xgb.DMatrix(data = mat[test,], label = mdl$pts[test])
watchlist = list(test = dtest, train = dtrain)


# fit model
bst <- xgb.train(data = dtrain, max.depth=6, nround=10000
                 , print.every.n = 50
                 , early.stop.round = 500
                 , maximize = FALSE
                 , watchlist=watchlist
                 , eta = .01
                 , objective = "count:poisson"
                 , gamma = .85
                 , subsample = .85)


preds <- predict(bst, dtrain)
preds <- data.table(id = train, pred = preds)
setkey(preds, id)
setkey(mdl, id)
train_rslt <- mdl[preds][, .(match_id, team_id, home, season_year, pts, pred)]
train_rslt <- dcast.data.table(train_rslt
                               , match_id + season_year ~  home
                               , value.var = list("pts", "pred"))
train_rslt[, .(correct = sum(sign(pts_0 - pts_1) == sign(pred_0 - pred_1))
               , total = .N
               , pcnt = sum(sign(pts_0 - pts_1) == sign(pred_0 - pred_1)) / .N)
           , .(season_year)]


preds <- predict(bst, dtest)
preds <- data.table(id = test, pred = preds)
setkey(preds, id)
setkey(mdl, id)
train_rslt <- mdl[preds][, .(match_id, team_id, home, season_year, pts, pred)]
train_rslt <- dcast.data.table(train_rslt
                               , match_id + season_year ~  home
                               , value.var = list("pts", "pred"))
train_rslt[, .(correct = sum(sign(pts_0 - pts_1) == sign(pred_0 - pred_1))
               , total = .N
               , pcnt = sum(sign(pts_0 - pts_1) == sign(pred_0 - pred_1)) / .N)
           , .(season_year)]



