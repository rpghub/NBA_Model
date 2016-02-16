# 538 elo model adapted to pbp data

library(data.table)
library(Rcpp)

setwd("C:/Projects/NBA_Model/Models")
pbp_elo <- fread("pbp_model.csv")

# define Rcpp elo model -------------------------------------------------------

# Computes elo ratings after each game and returns squared error between
# predicted and actual outcomes
#
# Args:
#   team_idx: index of team's elo rating in curr_elo vector
#   opp_idx: index of opp's elo rating in curr_elo vector
#   mov: margin of victory
#   result: 1 for win .5 for tie 0 for loss (in relation to team_idx team)
#   pos: number of possesions summariesed by record
#   new_season: dummy var for if game is first game of the season
#   curr_elo: vector of starting elo ratings for each team
#   k: scales impact of results on elo rating (proportional to pos)
#   h: home field advantage parameter
#   elo: elo rating after result of the given row
#   elo_start: elo rating before result of given row
#   opp_elo: elo rating after result of the given row
#   opp_elo_start: elo rating before result of given row
#   est: estimated pre-result probability
#   error: squared error
#   c1: margin of victory additive constant 1
#   c2: margin of victory additive constant 2
#   p1: margin of victory multiplier constant 1
#   p2: margin of victory multiplier constant 2
#
# Returns:
#   Updates the vectors elo, elo_start, opp_elo, opp_elo_start
#   est, and error with values based on model results
#   returns a scalar sum of square error

cppFunction('double elo1(SEXP team_idx, SEXP opp_idx, SEXP mov, SEXP result
            , SEXP pos, SEXP new_season, SEXP curr_elo, int k, int h
            , SEXP elo, SEXP elo_start, SEXP opp_elo, SEXP opp_elo_start
            , SEXP est, SEXP error, double c1, double c2, double p1
            , double p2) {
            Rcpp::IntegerVector xteam_idx(team_idx);
            Rcpp::IntegerVector xopp_idx(opp_idx);
            Rcpp::NumericVector xmov(mov);
            Rcpp::NumericVector xresult(result);
            Rcpp::NumericVector xpos(pos);
            Rcpp::NumericVector xnew_season(new_season);
            Rcpp::NumericVector xcurr_elo_tst(curr_elo);
            Rcpp::NumericVector xelo(elo);
            Rcpp::NumericVector xelo_start(elo_start);
            Rcpp::NumericVector xopp_elo(opp_elo);
            Rcpp::NumericVector xopp_elo_start(opp_elo_start);
            Rcpp::NumericVector xest(est);
            Rcpp::NumericVector xerror(error);
            
            Rcpp::NumericVector xcurr_elo(xcurr_elo_tst.size());
            
            int n = xteam_idx.size();
            int result_sign = 1;            
            
            double elo_diff = 0, m = 0, mu = 0, chng = 0, tot_error = 0;
            
            for (int i = 0; i < xcurr_elo_tst.size(); i++)
              xcurr_elo[i] = xcurr_elo_tst[i];
            
            for (int i = 0; i < n; i++){
              if (xnew_season[i] == 1){
                xcurr_elo[xteam_idx[i] - 1] = .75 * xcurr_elo[xteam_idx[i] - 1] + .25 * 1505;
                xcurr_elo[xopp_idx[i] - 1] = .75 * xcurr_elo[xopp_idx[i] - 1] + .25 * 1505;
              }
              xelo_start[i] = xcurr_elo[xteam_idx[i] - 1];
              xopp_elo_start[i] = xcurr_elo[xopp_idx[i] - 1];
              elo_diff = xcurr_elo[xteam_idx[i] - 1] - xcurr_elo[xopp_idx[i] - 1] + h;
              if (xresult[i] == .5 & elo_diff < 0){
                result_sign = 1;
              } else if (xresult[i] == .5) {
                result_sign = 1;
              } else {
                result_sign = (2 * xresult[i]) - 1;
              }
              m = pow(xmov[i] + c1, p1) / (c2 + p2 * result_sign * elo_diff);
              mu = 1/(1+pow(10,-elo_diff/400));
              chng = xpos[i] / 200 * m * k * (xresult[i] - mu);
              xelo[i] = xcurr_elo[xteam_idx[i] - 1] + chng;
              xopp_elo[i] = xcurr_elo[xopp_idx[i] - 1] - chng;
              xcurr_elo[xteam_idx[i] - 1] = xelo[i];
              xcurr_elo[xopp_idx[i] - 1] = xopp_elo[i];
              xest[i] = mu;
              xerror[i] = pow((mu - xresult[i])* xpos[i] / 200, 2) ;
              tot_error += xerror[i];
            }
  
            return tot_error;
            }')


# set up pbp data for elo model -----------------------------------------------

# create new roster id from 1 to n_roster
n_pos <- 5000
rosters <- rbind(pbp_elo[, .(pos = sum(pos))
                         , .(roster_id = home_roster_id
                             , team_id = home_team_id)]
                 , pbp_elo[, .(pos = sum(pos))
                          , .(roster_id = visit_roster_id
                              , team_id = visit_team_id)])

rosters <- rosters[, .(pos = sum(pos)), .(roster_id, team_id)]
rosters[, roster_idx := seq_len(.N)]
rosters[pos < n_pos, roster_idx := as.integer(-1 * team_id)]
rosters[, roster_idx := .GRP, .(roster_idx)]

# create table based on collapsed rosters
setkey(rosters, roster_id, team_id)
setkey(pbp_elo, home_roster_id, home_team_id)
pbp_mdl <- rosters[, .(roster_id, team_id, roster_idx)][pbp_elo]
setnames(pbp_mdl, c("roster_id", "team_id", "roster_idx")
         , c("home_roster_id", "home_team_id", "home_roster_idx"))

setkey(rosters, roster_id, team_id)
setkey(pbp_mdl, visit_roster_id, visit_team_id)
pbp_mdl <- rosters[, .(roster_id, team_id, roster_idx)][pbp_mdl]
setnames(pbp_mdl, c("roster_id", "team_id", "roster_idx")
         , c("visit_roster_id", "visit_team_id", "visit_roster_idx"))

pbp_mdl <- pbp_mdl[, .(pos = sum(pos)
                       , home_pts = sum(home_pts)
                       , visit_pts = sum(visit_pts)
                       , mov = abs(sum(home_pts) - sum(visit_pts)))
                   , .(home_roster_idx, visit_roster_idx, match_id
                       , home_team_id, visit_team_id, game_date
                       , new_season, season_year)]

pbp_mdl <- pbp_mdl[, .(home_roster_idx
                       , visit_roster_idx, match_id
                       , home_team_id, visit_team_id, game_date
                       , new_season, season_year, pos, home_pts, visit_pts
                       , result = ifelse(home_pts == visit_pts
                                         , .5
                                         , ifelse(home_pts > visit_pts
                                                  , 1, 0))
                       , mov ,elo = 1500, elo_start = 1500
                       , opp_elo = 1500, opp_elo_start = 1500
                       , est = .5, error = 0)]


# starting values for each elo
curr_elo <- rep(1500, length(unique(c(pbp_mdl$visit_roster_idx
                                      , pbp_mdl$home_roster_idx))))

# create r function to call Rcpp elo model
f <- function (x){
  elo1(team_idx = pbp_mdl$home_roster_idx
       , opp_idx =  pbp_mdl$visit_roster_idx
       , mov = pbp_mdl$mov
       , result = pbp_mdl$result
       , pos = pbp_mdl$pos
       , new_season = pbp_mdl$new_season
       , curr_elo = curr_elo
       , k = x[1]
       , h = x[2] 
       , elo = pbp_mdl$elo
       , elo_start = pbp_mdl$elo_start
       , opp_elo = pbp_mdl$opp_elo
       , opp_elo_start = pbp_mdl$opp_elo_start
       , est = pbp_mdl$est
       , error = pbp_mdl$error
       , c1 = 3
       , c2 = 7.5
       , p1= .8
       , p2 = .006)
}

# fit model and check results -------------------------------------------------

# optimize the scale and home parameters
optim(c(20, 100), f)
f(c(20,100))


pbp_mdl[season_year == 2007 
        , .(elo_start = weighted.mean(elo_start, pos)
            , opp_elo_start = weighted.mean(opp_elo_start, pos)
            , pts = sum(home_pts), opp_pts = sum(visit_pts))
        , .(match_id)
        ][pts - opp_pts != 0
          , .(sum(ifelse((elo_start - opp_elo_start > 0 & pts - opp_pts > 0) 
                         | (elo_start - opp_elo_start < 0 & pts - opp_pts < 0)
                         , 1, 0)) / .N)]
