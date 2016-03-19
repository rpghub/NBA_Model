### process boxscore data for models

library(data.table)
library(Rcpp)
library(RODBC)

conn = odbcConnect("NBADB")
sql1 = "select * from stg.view_boxscore"
box = as.data.table(sqlQuery(conn,sql1))
box[, game_date := as.Date(game_date, "%Y-%m-%d")]

# add box possesions
box_tot <- box[, .(fga = sum(fga), fta = sum(fta), oreb = sum(oreb)
                   , dreb = sum(dreb), tov = sum(tov)
                   , fgm = sum(fgm))
               , .(match_id, team_id)]
box_tot[, tot_dreb := sum(dreb), .(match_id)]
box_tot[, pos := fga + .4 * fta - 1.07 * (oreb / (oreb + tot_dreb - dreb)) *
          (fga - fgm) + tov]
box_tot <- box_tot[, .(match_id, team_id, pos)]
box_tot[, pos := mean(pos), .(match_id)]
setkey(box_tot, match_id, team_id)
setkey(box, match_id, team_id)
box <- box[box_tot]
rm(box_tot)

# add days of rest
rst <- unique(box[, .(team_id, match_id, game_date, season_year)])
setkey(rst, team_id, game_date)
rst[, game_date_prior := shift(game_date, type = 'lag', 1L
                               , fill = as.Date('1980-01-01', "%Y-%m-%d"))
    , .(team_id)]
rst[game_date - game_date_prior == 1, rest := 0]
rst[game_date - game_date_prior == 2, rest := 1]
rst[game_date - game_date_prior == 3, rest := 2]
rst[game_date - game_date_prior == 4, rest := 3]
rst[is.na(rest), rest := 4]
rst <- rst[, .(team_id, match_id, rest)]
setkey(rst, team_id, match_id)
setkey(box, team_id, match_id)
box <- box[rst]
rm(rst)

# add opp team_id
box[, min_team_id := min(team_id), .(match_id)]
box[, max_team_id := max(team_id), .(match_id)]
box[, opp_team_id := ifelse(team_id == min_team_id, max_team_id, min_team_id)]
box[, min_team_id := NULL]
box[, max_team_id := NULL]

# export
setwd('C:/Projects/NBA_Model/Models')
write.csv(box, 'boxscore.csv', row.names = FALSE)
