###   reproduce 538 elo estimates using 538's nba data

library(data.table)
library(Rcpp)

setwd("C:/Projects/NBA Data/NBA-Data")
nba_elo <- fread("nbaallelo.csv")

# set up data for model -------------------------------------------------------
nba_elo[, date_game := as.Date(date_game, '%m/%d/%Y')]
nba_elo <- nba_elo[year_id == 2003]
nba_elo <- nba_elo[order(gameorder)]
nba_elo$team_id = as.character(nba_elo$team_id)
nba_elo$opp_id = as.character(nba_elo$opp_id)

# get starting elo from each team
nba_elo[, new_season := min(gameorder) ,.(team_id, year_id)]
nba_elo[, new_season := 1 * (gameorder == new_season)]
nba_elo[,order := frank(gameorder),.(team_id)]
curr_elo <- nba_elo[order == 1]$elo_i
curr_elo_start <- nba_elo[order == 1]$elo_i
names(curr_elo) <- nba_elo[order == 1]$team_id
idx <- data.table(team = names(curr_elo)
                  , team_idx = seq_len(length(curr_elo)))

setkey(idx, team)
setkey(nba_elo, team_id)
nba_elo <- nba_elo[idx]
setnames(idx, "team_idx", "opp_idx")
setkey(nba_elo, opp_id)
nba_elo <- nba_elo[idx]
nba_elo[order == 1, new_season := 0]
nba_elo[,order := NULL]
names(curr_elo) <- NULL 
setnames(nba_elo, '_iscopy', 'iscopy')
nba_elo <- nba_elo[iscopy == 0]
nba_elo <- nba_elo[order(gameorder)]


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

nba_elo[, elo := as.numeric(0)]
nba_elo[, opp_elo := as.numeric(0)]
nba_elo[, est := as.numeric(0)]
nba_elo[, error := as.numeric(0)]


f <- function(x){
  elo_calc(team_idx = nba_elo$team_idx
           , opp_idx = nba_elo$opp_idx
           , mov = abs(nba_elo$pts - nba_elo$opp_pts)
           , result = 1*(nba_elo$game_result =="W")
           , new_season = nba_elo$new_season
           , curr_elo = curr_elo
           , k = as.integer(x[1])
           , h = as.integer(x[2])
           , elo = nba_elo$elo
           , opp_elo = nba_elo$opp_elo
           , est = nba_elo$est
           , error = nba_elo$error
           , c1 = as.numeric(3)
           , c2 = as.numeric(7.5)
           , p1 = as.numeric(.8)
           , p2 = as.numeric(.006))}

a = optim(c(10, 50), f)

f(c(20, 100))

nba_elo[is_playoffs == 0
        , .(sum(ifelse((elo_i - opp_elo_i > 0 & game_result == "W")
                       | (elo_i - opp_elo_i < 0 & game_result == "L")
                       , 1, 0)) / .N)]
