### hierarchical poisson model with roster level random effects

library(rstan)
library(data.table)

rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores())

setwd("C:\\Projects\\NBA_Model\\Models")
pbp_fit <- fread("pbp_model.csv")
player <- fread("player.csv")
pbp_fit[, game_date := as.Date(game_date, "%Y-%m-%d")]

# model directory
setwd("C:\\Projects\\NBA_Model\\Models\\Poisson")


# season to fit on
pbp_fit <- pbp_fit[season_year == 2005]

# combine rosters with limited possesions into 'other' roster
n_pos <- 500
rstr <- rbind(pbp_fit[, .(roster_id = home_roster_id, pos
                          , team_id = home_team_id)]
              , pbp_fit[, .(roster_id = visit_roster_id, pos
                            ,team_id = visit_team_id)])

rstr <- rstr[, .(pos_tot = sum(pos)), .(roster_id, team_id)]
rstr[, roster_id_comb := ifelse(pos_tot < n_pos
                                , as.integer(-1*team_id)
                                , roster_id)]
rstr[, roster_idx_comb := .GRP, (roster_id_comb)]

setkey(rstr, roster_id, team_id)
setkey(pbp_fit, home_roster_id, home_team_id)
pbp_fit <- rstr[pbp_fit]
setnames(pbp_fit, c("roster_id", "team_id", "roster_id_comb", "pos_tot"
                    , "roster_idx_comb")
         , c("home_roster_id", "home_team_id", "home_roster_id_comb"
             , "home_pos_tot", "home_rstr_idx"))

setkey(pbp_fit, visit_roster_id, visit_team_id)
pbp_fit <- rstr[pbp_fit]
setnames(pbp_fit, c("roster_id", "team_id", "roster_id_comb", "pos_tot"
                    , "roster_idx_comb")
         , c("visit_roster_id", "visit_team_id", "visit_roster_id_comb"
             , "visit_pos_tot", "visit_rstr_idx"))

# aggregate with new combined rosters
pbp_fit <- pbp_fit[ , .(pos = sum(pos), home_pts = sum(home_pts)
                        , visit_pts = sum(visit_pts))
                    , .(visit_rstr = visit_roster_id_comb
                        , home_rstr = home_roster_id_comb
                        , home_rstr_idx, visit_rstr_idx
                        , home_team_id, visit_team_id
                        , home_rest, visit_rest
                        , game_date, season_year, match_id)]

rstr_comb <- rstr[, .(pos_tot = sum(pos_tot))
                  , .(rstr_idx = roster_idx_comb
                      , rstr_id = roster_id_comb
                      , team_id)]
rm(rstr)

# recast data long in terms of points 
pbp_fit_stan <- 
  rbind(pbp_fit[ ,.(rstr = home_rstr
                    , rstr_idx = home_rstr_idx
                    , team_id = home_team_id
                    , opp_rstr = visit_rstr
                    , opp_rstr_idx = visit_rstr_idx
                    , opp_team_id = visit_team_id
                    , pts = home_pts
                    , home = 1
                    , rest = ifelse(home_rest > 1, 2, 1)
                    , opp_rest = ifelse(visit_rest > 1, 2, 1)
                    , pos, game_date, season_year, match_id)]
        , pbp_fit[ ,.(rstr = visit_rstr
                      , rstr_idx = visit_rstr_idx
                      , team_id = visit_team_id
                      , opp_rstr = home_rstr
                      , opp_rstr_idx = home_rstr_idx
                      , opp_team_id = home_team_id
                      , pts = visit_pts
                      , home = 0
                      , rest = ifelse(visit_rest > 1, 2, 1)
                      , opp_rest = ifelse(home_rest > 1, 2, 1)
                      , pos, game_date, season_year, match_id)])

# 3 level categorical var for combinations of rest and opp rest
pbp_fit_stan[rest == opp_rest, rest_comb := 1]
pbp_fit_stan[rest == 1 & opp_rest == 2, rest_comb := 2]
pbp_fit_stan[rest == 2 & opp_rest == 1, rest_comb := 3]

# fit on first 3/4th of data
max_date <- summary(unique(pbp_fit$game_date))[5]
pbp_fit_stan_train <- pbp_fit_stan[game_date <= max_date]
pbp_fit_stan_test <- pbp_fit_stan[game_date > max_date]


# data for stan model
dat <- list(N_roster = nrow(rstr_comb)
            , N = nrow(pbp_fit_stan_train)
            , y = pbp_fit_stan_train$pts
            , roster = pbp_fit_stan_train$rstr_idx
            , opp_roster = pbp_fit_stan_train$opp_rstr_idx
            , home = pbp_fit_stan_train$home
            , pos = pbp_fit_stan_train$pos
            , rest = pbp_fit_stan_train$rest_comb
            , N_new = nrow(pbp_fit_stan_test)
            , roster_new = pbp_fit_stan_test$rstr_idx
            , opp_roster_new = pbp_fit_stan_test$opp_rstr_idx
            , home_new = pbp_fit_stan_test$home
            , pos_new = pbp_fit_stan_test$pos
            , rest_new = pbp_fit_stan_test$rest_comb)

fit <- stan("poisson_roster_rest.stan", data = dat, iter = 1000, chains = 4)

# check fit
print(fit, pars = "o_roster")
print(fit, pars = "d_roster")
print(fit, pars = "a_roster")
print(fit, pars = "alpha")
print(fit, pars = "beta")
print(fit, pars = "beta_o_rest")

plot(fit, pars = "o_roster")
plot(fit, pars = "d_roster")
plot(fit, pars = "a_roster")
plot(fit, pars = "alpha")
plot(fit, pars = "beta")
plot(fit, pars = "beta_o_rest")


# check results
fit.vars <- extract(fit)

# check training data first
train = as.data.table(melt(fit.vars$y_sim))
train = cbind(train[order(iterations, Var2)]
              , pbp_fit_stan_train[, .(match_id, home, pts)])
train <- train[, .(home_pts_est = sum(value * home)
                   , visit_pts_est = sum(value * (1 - home))
                   , home_pts = sum(pts * home)
                   , visit_pts = sum(pts * (1 - home)))
               , .(match_id, iterations)]

train <- train[home_pts != visit_pts
               , .(home_win =  home_pts > visit_pts
                   , home_win_est = home_pts_est > visit_pts_est
                   , match_id, iterations)
               ][, .(pcnt = sum(home_win_est) / .N)
                 , .(match_id, home_win)]

# raw correct percentage
train[, .(pcnt = sum(pcnt > .5 & home_win == TRUE 
                     | pcnt < .5 & home_win == FALSE) /.N)]

# percentage by predicted percentage
train[, .(pcnt_act = round(sum(home_win) / .N,3), win_act = .N)
      , .(pcnt_est_bin = cut(pcnt, seq(0,1,.1)))
      ][order(pcnt_est_bin)]


# test results
test = as.data.table(melt(fit.vars$y_new))
test = cbind(test[order(iterations, Var2)]
              , pbp_fit_stan_test[, .(match_id, home, pts)])
test <- test[, .(home_pts_est = sum(value * home)
                   , visit_pts_est = sum(value * (1 - home))
                   , home_pts = sum(pts * home)
                   , visit_pts = sum(pts * (1 - home)))
               , .(match_id, iterations)]

test <- test[home_pts != visit_pts
               , .(home_win =  home_pts > visit_pts
                   , home_win_est = home_pts_est > visit_pts_est
                   , match_id, iterations)
               ][, .(pcnt = sum(home_win_est) / .N)
                 , .(match_id, home_win)]

# raw correct percentage
test[, .(pcnt = sum(pcnt > .5 & home_win == TRUE 
                     | pcnt < .5 & home_win == FALSE) /.N)]

# percentage by predicted percentage
test[, .(pcnt_act = round(sum(home_win) / .N,3), win_act = .N)
      , .(pcnt_est_bin = cut(pcnt, seq(0,1,.1)))
      ][order(pcnt_est_bin)]



