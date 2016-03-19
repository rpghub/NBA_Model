###   reproduce 538 elo estimates using 538's nba data

library(data.table)
library(Rcpp)


setwd("C:\\Projects\\NBA_Model\\Models")
box <- fread("boxscore.csv")
box[, game_date := as.Date(game_date, "%Y-%m-%d")]

# create function to calculate elo
cppFunction('double elo_calc(SEXP team_idx, SEXP opp_idx, SEXP mov, SEXP result
            ,SEXP new_season, SEXP curr_elo, int k, int h
            , SEXP elo, SEXP opp_elo, SEXP est, SEXP error
            , double c1, double c2, double p1, double p2) {
            Rcpp::IntegerVector xteam_idx(team_idx);
            Rcpp::IntegerVector xopp_idx(opp_idx);
            Rcpp::NumericVector xmov(mov);
            Rcpp::NumericVector xresult(result);
            Rcpp::NumericVector xnew_season(new_season);
            Rcpp::NumericVector xcurr_elo_tst(curr_elo);
            Rcpp::NumericVector xelo(elo);
            Rcpp::NumericVector xopp_elo(opp_elo);
            Rcpp::NumericVector xest(est);
            Rcpp::NumericVector xerror(error);
            
            Rcpp::NumericVector xcurr_elo(xcurr_elo_tst.size());
            
            int n = xteam_idx.size();
            
            double elo_diff = 0, m = 0, mu = 0, chng = 0, tot_error = 0;
            
            for (int i = 0; i < xcurr_elo_tst.size(); i++)
            xcurr_elo[i] = xcurr_elo_tst[i];
            
            
            for (int i = 0; i < n; i++){
            if (xnew_season[i] == 1){
            xcurr_elo[xteam_idx[i] - 1] = .75 * xcurr_elo[xteam_idx[i] - 1] + .25 * 1505;
            xcurr_elo[xopp_idx[i] - 1] = .75 * xcurr_elo[xopp_idx[i] - 1] + .25 * 1505;
            }
            elo_diff = xcurr_elo[xteam_idx[i] - 1] - xcurr_elo[xopp_idx[i] - 1] + h; 
            m = pow(xmov[i] + c1, p1) / (c2 + p2 * (2 * xresult[i] - 1) * elo_diff);
            mu = 1/(1+pow(10,-elo_diff/400));
            chng = m * k * (xresult[i] - mu);
            xelo[i] = xcurr_elo[xteam_idx[i] - 1] + chng;
            xopp_elo[i] = xcurr_elo[xopp_idx[i] - 1] - chng;
            xcurr_elo[xteam_idx[i] - 1] = xelo[i];
            xcurr_elo[xopp_idx[i] - 1] = xopp_elo[i];
            xest[i] = mu;
            xerror[i] = pow(mu - xresult[i], 2);
            tot_error += xerror[i];
            }
            
            return tot_error;
            }
            ')

# aggregate to game level data
gm <- box[, .(pts = sum(pts)
              , home_id = as.integer(max(ifelse(home == 1, team_id
                                                , opp_team_id)))
              , visit_id = as.integer(max(ifelse(home == 1, opp_team_id
                                                 , team_id))))
          , .(match_id, team_id, home, game_date, season_year)]
gm[, home_pts := sum(pts * (home == 1)), .(match_id)]
gm[, visit_pts := sum(pts * (home == 0)), .(match_id)]



# set up data for model -------------------------------------------------------
gm <- gm[order(season_year, game_date)]
gm[, gameorder := seq_len(.N), .(team_id, season_year)]

# new season
gm[, new_season := min(gameorder) ,.(team_id, season_year)]
gm[, new_season := 1 * (gameorder == new_season)]

# replace game order with overal order
gm <- gm[order(game_date)]
gm[, gameorder := seq_len(.N)]

# only keep home games
gm <- gm[home == 1]

# add in fields to be filled by elo function
gm[, elo := as.numeric(0)]
gm[, opp_elo := as.numeric(0)]
gm[, est := as.numeric(0)]
gm[, error := as.numeric(0)]
curr_elo <- rep(1500, 30)


# helper function to call elo
f <- function(x){
  elo_calc(team_idx = gm$home_id
           , opp_idx = gm$visit_id
           , mov = abs(gm$home_pts - gm$visit_pts)
           , result = ifelse(gm$home_pts > gm$visit_pts, 1, 0)
           , new_season = gm$new_season
           , curr_elo = curr_elo
           , k = as.integer(x[1])
           , h = as.integer(x[2])
           , elo = gm$elo
           , opp_elo = gm$opp_elo
           , est = gm$est
           , error = gm$error
           , c1 = as.numeric(3)
           , c2 = as.numeric(7.5)
           , p1 = as.numeric(.8)
           , p2 = as.numeric(.006))}


f(c(20, 100))

# create table of team starting and finishing elo
home_elo <- gm[, .(match_id, gameorder, new_season,  team_id = home_id, elo
                   , season_year)]
visit_elo <- gm[, .(match_id, gameorder, new_season, team_id = visit_id
                    , elo = opp_elo, season_year)]
elo <- rbind(home_elo, visit_elo)
elo <- elo[order(gameorder)]
elo[, elo_prev := shift(elo, type = "lag", 1L, fill = 1500), .(team_id)]
min_season_year <- min(elo$season_year)
elo[season_year > min_season_year & new_season == 1
    , elo_prev := .75 * elo_prev + .25 * 1505]
elo <- elo[, .(match_id, team_id, elo_start = elo_prev, elo_end = elo)]
rm(home_elo, visit_elo, min_season_year)

# export
setwd("C:\\Projects\\NBA_Model\\Models")
write.csv(elo, "boxscore elo.csv", row.names = FALSE)

