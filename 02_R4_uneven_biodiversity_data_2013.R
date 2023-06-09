# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
#
# Uneven biodiversity sampling across redlined urban areas in the United States, EcoEvoRxiv, in review Nature Human Behavior
#
# Diego Ellis-Soto, Millie Chapman, Dexter Locke
#
# Contact information: Diego.ellissoto@yale.edu
#
# The aim of this script is to perform analysis on estimating the sampling density and survey completeness of bird biodiversity across 195 urban areas across the United States. 
#
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

# [0] Load packages and holc polygon ####
require(rgdal)
require(stringr)
require(tidyverse)
require(reshape2)
require(gridExtra)
require(sf)
require(sp)
require(raster)
require(plyr)
require(purrr)
require(dplyr)
require(janitor)
require(mgcv)
library(KnowBR)
require(patchwork)
require(sjPlot)
data("adworld")
conflict_prefer("mutate", "dplyr")
conflict_prefer("summarize", "dplyr")
conflict_prefer("summarise", "dplyr")
cm.cols1=function(x,bias=1) { colorRampPalette(c('grey90','steelblue4','steelblue1','gold','red1','red4'),bias=bias)(x)}

# Color palette for redlining
holc_pal <- c('#92BC6B' # green
              , '#92C7C9' # blue
              , '#E7DC6B' # yellow
              , '#E47D67' # red
)#, '#A9A9A9' # dark gray)


# Directories:
# indir: Contains the raw bird biodiversity data downloaded from GBIF as an SF object, for each HOLC polygon separately, stored as a .Rdata file
# outdir: Folder where we will store our created outputs
indir = '/Users/diegoellis/Desktop/HOLC_newest/Download_GBIF_HOLC' 
outdir = '/Users/diegoellis/Desktop/CSV_tables/'

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# Load Holc Polygons from the Mapping Inequality project form the University of richmond
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

holc <- st_read('/Users/diegoellis/Downloads/shapefile/holc_ad_data.shp') %>% 
  sf::st_cast('POLYGON') %>% # IMPORTANT
  dplyr::filter(!st_is_empty(.)) %>% 
  sf::st_make_valid(.) %>% 
  tibble::rowid_to_column() %>% 
  dplyr::mutate(  id = paste(state, city, holc_id, holc_grade, rowid, sep = '_')
                  , city_state = paste0(city, ', ', state)
                  , area_holc_km2 = as.double(st_area(.) / 1e+6)) %>% 
  dplyr::select(id, state, city, holc_id, holc_grade, city_state, area_holc_km2) 

# Calculate the area of holc polygons
holc_area <-  holc %>% dplyr::select(city, holc_grade, area_holc_km2) %>% dplyr::group_by(holc_grade) %>% dplyr::summarise(area_sum = sum(area_holc_km2)) %>% dplyr::filter(holc_grade != 'E')  %>% as_tibble() %>% dplyr::select(-geometry)

# List all .Rdata files in our input folder that contain bird biodiversity data:
aves_obs = (list.files('/Users/diegoellis/Desktop/HOLC_newest/Download_GBIF_HOLC', pattern = 'Aves_all_observations.Rdata', full.names = T))

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# [1] Loop through all our HOLC polygons with bird biodiversity data and count the number of observations per single HOLC polygon, the raw building block to calculate sampling density ####
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

for(i in unique(aves_obs)){
  print(i)
  
  if(!any(str_detect(aves_obs, pattern = i))==TRUE){
    print(paste0(i, ' has no biodiversity data'))
    next
  }
  
  biodiv_data = aves_obs[str_detect(aves_obs, pattern = i)]
  
  # Load the single polygon with bird biodiversity data
  results <- sapply(biodiv_data, function(x) mget(load(x)), simplify = TRUE) 
  
  # Keep only desired columns as GBIF has 200+ columns
  mycols = c('species',
             'family',
             'genus',
             'decimalLongitude',
             'decimalLatitude',
             'collectionCode',
             'collectionID',
             'institutionCode',
             'year',
             'city',
             'city_state',
             'holc_id',
             'holc_grade',
             'species',
             'id')
  
  results <- lapply( results , "[", , mycols) 
  
  df <- do.call(rbind, results)
  
  make_n_observations = data.frame(
    # holc_polygon = unique(df$id),
    holc_grade = unique(df$holc_grade),
    holc_polygon = gsub('.Rdata','', basename(i) ),
    sum_bird_obs = nrow(df),
    city = unique(df$city),
    city_state = unique(df$city_state)
  )
  
  write.table(make_n_observations, file = paste0(outdir, "/R1_biodiv_sum_bird_obs_by_holc_id_1933_2022.csv"), append = T, row.names = F,col.names = F, sep = ",")
  
  # --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
  # [2]  Divide biodiversity sampling by year and collection type (iNaturalist, ebird, other) ####
  # --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
  
  # 1933-2022  
  tmp_by_yar = plyr::ddply(df, 'year', function(y){
    plyr::ddply(y, 'holc_grade', function(z){
      data.frame(year = unique(z$year),
                 holc_grade = unique(z$holc_grade),
                 #         institutionCode_review = unique(z$institutionCode_review),
                 # holc_id = unique(z$id),
                 n_obs = nrow(z))
    })
  })
  
  write.table(tmp_by_yar, file = paste0(outdir, "/R1_biodiv_trend_by_time_holc_id_1933_2022.csv"), append = T, row.names = F,col.names = F, sep = ",")
  
  # 2000-2020
  df = df %>%  data.frame() %>% dplyr::filter(year >= 2000 & year <= 2020)
  
  # Some ebird records have atlas data
  df =   df %>% mutate(institutionCode_review = case_when(
    #   collectionCode == 'GBBC'  ~  'great backyard bird count',
    collectionCode == 'GBBC'  ~  'ebird',
    collectionCode == 'EBIRD'  ~  'ebird',
    str_detect(institutionCode, 'iNaturalist') ~ 'iNaturalist',
    TRUE ~ 'other'
  )
  )
  
  tmp = data.frame(table(df$institutionCode_review))
  
  if(  !"other" %in% unique(tmp$Var1)){ 
    print(' No other obs making a column of type other with observation 0')
    
    tmp2 = data.frame(Var1 = as.factor('other'), Freq = 0)
    tmp = rbind(tmp, tmp2)
  }
  
  if( !"iNaturalist" %in% unique(tmp$Var1) ){
    print(' No iNaturalist obs making a column of type other with observation 0')
    
    tmp2 = data.frame(Var1 = as.factor('iNaturalist'), Freq = 0)
    tmp = rbind(tmp, tmp2)
  }
  
  if( !"ebird" %in% unique(tmp$Var1) ){
    print(' No ebird obs making a column of type other with observation 0')
    
    tmp2 = data.frame(Var1 = as.factor('ebird'), Freq = 0)
    tmp = rbind(tmp, tmp2)
  }
  
  tmp$holc_polygon <- unique(gsub('.Rdata','', basename(i) ))
  
  write.table(tmp, file = paste0(outdir, "/R1_biodiv_col_code_by_holc_id_2000_2020.csv"), append = T, row.names = F,col.names = F, sep = ",")
  
}

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# [3] Calculate survey completeness: Out of 195 cities, a few cities cannot be calculated (Houston, San Antonio) ####
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

outdir <- "/Users/diegoellis/Desktop/Estiamtors/"

cities_i_want = unique(holc$city)[i]

for(i in cities_i_want ){
  ciudad = basename(i)
  print(ciudad)
  
  if(!any(str_detect(aves_obs, pattern = i))==TRUE){
    print(paste0(i, ' has no biodiversity data'))
    next
  }
  
  biodiv_data = aves_obs[str_detect(aves_obs, pattern = i)]
  
  results <- sapply(biodiv_data, function(x) mget(load(x)), simplify = TRUE) 
  
  mycols = c('species',
             'family',
             'genus',
             'decimalLongitude',
             'decimalLatitude',
             'collectionCode',
             'institutionCode',
             'year',
             'city',
             'city_state',
             'holc_id',
             'holc_grade',
             'species')
  
  results <- lapply( results , "[", , mycols) 
  results <- lapply( results , "[", , -13)# remove species which is often duplicates. 
  
  # Load all SF objects into a sngle list
  gbif_holc_int <- do.call(rbind, results)
  gbif_holc_int$Counts <- 1
  
  # city_HOLC = holc
  city_HOLC = holc[holc$city == i,]
  
  dat <- gbif_holc_int[,c("species","decimalLongitude","decimalLatitude", "Counts",
                          'holc_id', 'holc_grade')]
  names(dat)[2:3] <- c('longitude', 'latitude')
  
  dat = data.frame(dat )%>% dplyr::select(-geometry)
  
  dir.create(paste0(outdir, i))
  setwd(paste0(outdir, i))
  
  if(all(is.na(dat$holc_id))){next}
  data("adworld")
  
  city_HOLC = city_HOLC[!st_is_empty(city_HOLC),] %>% dplyr::select(-holc_id)# remove empty polygons
  city_HOLC_sp = as(city_HOLC, 'Spatial') # REMOVE NA polygons ! 
  # KnowBPolygon needs sp object
  
  KnowBPolygon(data=dat, format="A", estimator=1,
               shape=city_HOLC_sp, 
               shapenames="id", # Set to ID ! #### # holc_id
               jpg=TRUE,
               Maps=TRUE,
               save="RData",
               legend=TRUE,
               colscale=cm.cols1(100))
  
}

# Once this loop is completed,  proceed on analysing the estimators

indir <- "/Users/diegoellis/Desktop/Estimators/"
estimator_data <- paste0(list.files(indir, full.names = T), pattern = '/Estimators.Rdata')
estimator_data[!file.exists(estimator_data)] # Houston, San Antonio did not run ####
estimator_data <- estimator_data[file.exists(estimator_data)]
listForFiles <- list()

# Load all estimators together into object df
for(i in 1:length(unique(estimator_data))){
  print(i)
  load(estimator_data[i])
  listForFiles[[i]] <- estimators
  city_name <- unique(estimator_data)[i]
  city_name <- gsub(indir, '',city_name)
  city_name <- gsub('/Estimators.Rdata','',city_name)
  listForFiles[[i]]$City <- city_name
  rm(estimators)
}

df <- do.call(rbind.data.frame, listForFiles)
df$holc_grade <- substr(df$Area, 1, 1)
df$holc_grade <- as.factor(df$holc_grade)
# df = df[df$holc_grade %in% c('A', 'B', 'C', 'D'),]

# Unite:  check left join with holc:
df$id <- df$Area
df_2 = left_join(df, holc[c('id', 'holc_grade')], by = 'id') %>% mutate(holc_grade = holc_grade.y) %>% dplyr::select(-geometry, -holc_grade.x, -holc_grade.y, -Area) 
df_2$City = substring(df_2$City, 2)
write.csv(df_2, file = paste0('/Users/diegoellis/Desktop/Nature_Human_Behavior/CSV_tables/bird_completeness_HOLC_cities_2022_R1.csv'))

# Store completeness
df_completeness = plyr::ddply(df_2, 'holc_grade', function(x){
  data.frame(
    Completeness = mean(x$Completeness, na.rm=T),
    Slope = mean(x$Slope, na.rm=T),
    Richness = mean(x$Richness, na.rm=T),
    Observed_.richness = mean(x$Observed.richness, na.rm=T),
    Records = mean(x$Records, na.rm=T)
  )
})
df_completeness = df_completeness[df_completeness$holc_grade %in% c('A', 'B', 'C', 'D'),]

# Load data frames in list into a single data frame :
write.csv(df_completeness, file = paste0('/Users/diegoellis/Desktop/Nature_Human_Behavior/bird_completeness_HOLC_summary_2022_R1.csv'))

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# [4] Calculate bird biodiversity coldspots #### 
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

# Calculate Cold-Hot spots based on La Sorte et al. 2020 (Area is the primary correlate of annual and seasonal patterns of avian species richness in urban green spaces) who uses the rationale of Lobo et al. 2018. Instead of removing these areas, we designate them as biodiversity coldspots

df <-  df_2
# How many survets are poorly surveyed:
df$ratio_n_obs_sp_richness <- round( (df$Records / df$Observed.richness) , 2)

undersampled_ratio <- which(df$ratio_n_obs_sp_richness < 3)
# Poorly sampled: Slope is above 0.3
undersampled_slope <- which(df$Slope > 0.3)

undersampled_completeness <- which(df$Completeness < 50)
undersampled_regions <- c(undersampled_ratio, undersampled_slope, undersampled_completeness)
undersampled_regions = unique(undersampled_regions)
# A total of 2992 are undersampled
length(undersampled_regions)

coldspots <- df[undersampled_regions,]


coldspot_regions <- plyr::ddply(coldspots, 'holc_grade', function(x){
  data.frame(
    n_row_total_n_coldspot_polygons = nrow(x),
    percent_coldspots = (  ( nrow(x) / nrow(coldspots) ) * 100 )
  )
})

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# [5] Add climatic data ####
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

# Chelsa Bioclims available at chelsa-bioclim.org

# Load and project climatic layers
indir <- '/Users/diegoellis/projects/Manuscripts_collab/phySDM/Input/Env_layers/Bioclims/'
env <- stack(list.files(indir, full.names = T))
env <- projectRaster(env, crs = '+proj=longlat +datum=WGS84 +no_defs')
names(env)

# Get the centroids of holc polygons
holc_centroid = st_centroid(holc)
holc_centroids = st_coordinates(holc_centroid)
holc_centroids = cbind(holc_centroid, holc_centroids)

holc_centroids_df = data.frame(holc_centroids)
# Remove coordinates with NA in this case FL_Jacksonville_B3_B_1404
which(is.na(holc_centroids_df$X))
which(is.na(holc_centroids_df$Y))
holc_centroids_df = holc_centroids_df[-1404,]

# Extract raster values:
holc_centroids_df = SpatialPointsDataFrame(holc_centroids_df,
                                           coords = holc_centroids_df[,c('X', 'Y')],
                                           proj4string =CRS("+proj=longlat +datum=WGS84")
)
holc_centroids_df$temperature = extract(env[[1]], holc_centroids_df)
holc_centroids_df$precip = extract(env[[2]], holc_centroids_df)

holc_centroids_sf = sf::st_as_sf(holc_centroids_df)
st_crs(holc_centroids_sf)  = 4326
holc_centroids_sf_df = data.frame(holc_centroids_sf) %>% dplyr::select(temperature, precip, id)

# Delete holc polygon FL_Jacksonville_B3_B_1404 which has an NA coordinate
holc_df = data.frame(holc) %>% dplyr::select(id, state, city, holc_grade)
holc_df = holc_df[-1404,]

all = left_join( holc_centroids_sf_df, holc_df, by = 'id')
all$t = round(all$temperature, 1)
all$p = round(all$precip, 1)
all$t_2 = all$t ^ 2
write.csv(all, file = paste0(outdir, 'R1_climatic_data_cities.csv'))

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# [6] End of bird biodiversity data preparation steps, proceeding with analysis and plotting ####
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# [7] Plot temporal trends 1933-2022 and 2000-2020 ####
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

# Load 2000-2020 data
temporal_2000_2020 = read.table(paste0(outdir, "/R1_biodiv_col_code_by_holc_id_2000_2020.csv"), header= T,sep=',')
names(temporal_2000_2020) <- c('Type', 'Sum', 'holc_polygon_id')
temporal_2000_2020$holc_grade = substr(sub(".*?_", "", (sub("_.*?", "", sub("_.*?", "", temporal_2000_2020$holc_polygon_id))) ), 1,1) # 2 holc polygons need to be correctly labeled based on the previous regex. These are all HOLC B polygons
# temporal_2000_2020[which(temporal_2000_2020$holc_grade =='2'),]$holc_grade <- 'B'
temporal_2000_2020 = temporal_2000_2020 %>% filter(holc_grade  %in% c('A', 'B', 'C', 'D')) 

# A few HOLC polygons do not contain any bird observations from 2000-2020 which makes total sense
temporal_2000_2020 %>% filter(Sum > 0) %>% summarise(length(unique(holc_polygon_id)))
sum(temporal_2000_2020$Sum)  # Most of bird biodiversity data in these cities was collected from 2000-2020
# temporal_2000_2020$Sum = as.numeric(temporal_2000_2020$Sum)
# Load 1933-2022 data
temporal_trend = read.table(paste0(outdir, "/R1_biodiv_trend_by_time_holc_id_1933_2022.csv"), header= T,sep=',')
# names(temporal_trend) <- c('Year','holc_grade','Type','holc_polygon_id', 'Sum')
names(temporal_trend) <- c('Year','holc_grade', 'Sum')
temporal_trend = temporal_trend %>% filter(holc_grade != 'E')
sum(temporal_2000_2020$Sum,na.rm=T) / sum(temporal_trend$Sum,na.rm=T) # 77.8 % of biodiversity data collected in last 20 years ! 

temporal_all_data = ddply(temporal_trend, 'holc_grade', function(x){
  ddply(x, 'Year', function(z){
    
    data.frame(
      Year = unique(z$Year),
      holc_grade = unique(z$holc_grade),
      n_obs = sum(z$Sum,na.rm=T)
      #    n_obs_cum = cumsum(z$Sum)
    )
    
  })
})

tmpppp = temporal_all_data %>% group_by(holc_grade, Year) # %>% mutate(cumsum = cumsum(n_obs))

trend_A = tmpppp %>% filter(holc_grade == 'A') %>% mutate(cumsum_n_obs = cumsum(n_obs)) %>% left_join(holc_area) %>% mutate(sampling_density = cumsum_n_obs /area_sum )

trend_B  = tmpppp %>% filter(holc_grade == 'B') %>% mutate(cumsum_n_obs = cumsum(n_obs)) %>% left_join(holc_area) %>% mutate(sampling_density = cumsum_n_obs /area_sum )

trend_C  = tmpppp %>% filter(holc_grade == 'C') %>% mutate(cumsum_n_obs = cumsum(n_obs)) %>% left_join(holc_area) %>% mutate(sampling_density = cumsum_n_obs /area_sum )

trend_D  = tmpppp %>% filter(holc_grade == 'D') %>% mutate(cumsum_n_obs = cumsum(n_obs)) %>% left_join(holc_area) %>% mutate(sampling_density = cumsum_n_obs /area_sum )

temporal_all_data = rbind(trend_A,trend_B,trend_C,trend_D)

# Plot temporal trend: 2000-2020
temporal_all_data %>% 
  filter(Year >= 2000 & Year <= 2020) %>% 
  ggplot(aes(x = Year, y = sampling_density), fill = holc_grade) + 
  geom_line(aes(color = holc_grade), size = 1) +
  scale_color_manual(values = holc_pal) +
  theme_bw(16) + 
  theme(legend.position = 'none') + 
  ylab('Sampling density in 1km^2') 
NULL

ggsave('/Users/diegoellis/Desktop/temporal_biodiv_2000_2020.png'
       , width = 4.42
       , height = 5
       , dpi = 600
)

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# [8] Model trends over time ####
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

# Signifciantly different across HOLC grades through time. A is significantly different from C and D
temporal_all_data_tmp =data.frame(temporal_all_data)
temporal_all_data_tmp$Year <- as.integer(temporal_all_data_tmp$Year)
# summary(gam(sampling_density ~ Year * holc_grade, data = temporal_all_data_tmp))

# Do the same but for 2000-2020 onwards:
summary(gam(sampling_density ~ Year * holc_grade, data = temporal_all_data_tmp[temporal_all_data_tmp$Year %in% c(2000:2020),]))

model_sampling = glm((sampling_density) ~ Year * holc_grade, data = temporal_all_data_tmp[temporal_all_data_tmp$Year %in% c(2000:2020),])
model_sampling |> tab_model( show.aic = TRUE)

tab_model(model_sampling, auto.label = T)



# Survey completeness:
survey_completeness = read.csv('/Users/diegoellis/projects/Proposals_funding/Yale_internal_grants/Redlining/2022/Data/All_cities/bird_completeness_HOLC_cities_2022.csv')

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# [10] Plot by observation type ####
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

ebird  = temporal_2000_2020 %>% filter(Type =='ebird')
inat = temporal_2000_2020 %>% filter(Type =='iNaturalist')
other = temporal_2000_2020 %>% filter(Type =='other')

ebird_sampling_density <- ddply(ebird, 'holc_grade', function(x){
  sampling_sum = sum(x$Sum)
})
ebird_sampling_density_df = left_join(ebird_sampling_density, holc_area)
ebird_sampling_density_df$sampling_density <- ebird_sampling_density_df$V1 / ebird_sampling_density_df$area_sum
ebird_sampling_density_df = ebird_sampling_density_df %>% filter(holc_grade != 'E')

inat_sampling_density <- ddply(inat, 'holc_grade', function(x){
  sampling_sum = sum(x$Sum)
})
inat_sampling_density_df = left_join(inat_sampling_density, holc_area)
inat_sampling_density_df$sampling_density <- inat_sampling_density_df$V1 / inat_sampling_density_df$area_sum
inat_sampling_density_df = inat_sampling_density_df %>% filter(holc_grade != 'E')

other_sampling_density <- ddply(other, 'holc_grade', function(x){
  sampling_sum = sum(x$Sum)
})

other_sampling_density_df = left_join(other_sampling_density, holc_area)
other_sampling_density_df$sampling_density <- other_sampling_density_df$V1 / other_sampling_density_df$area_sum
other_sampling_density_df = other_sampling_density_df %>% filter(holc_grade != 'E')

inat_sampling_density_plot = inat_sampling_density_df %>%
  ggplot(aes(holc_grade, sampling_density, fill = holc_grade)) +
  geom_col() + 
  scale_fill_manual(values = holc_pal) + 
  theme_bw(16) + 
  theme_classic(16) +
  labs(title='iNaturalist') + 
  theme(legend.position = 'none') + 
  ylab('Sampling density in 1km^2') +
  theme(axis.title.x=element_blank(),
        axis.text.x=element_blank()
  )
NULL

other_sampling_density_plot = other_sampling_density_df %>%
  ggplot(aes(holc_grade, sampling_density, fill = holc_grade)) +
  geom_col() + 
  scale_fill_manual(values = holc_pal) + 
  theme_bw(16) + 
  theme_classic(16) +
  labs(title='Other') + 
  theme(legend.position = 'none') + 
  ylab('Sampling density in 1km^2') +
  xlab('HOLC Grade') +
  theme(
    axis.title.y=element_blank(),
  ) + 
  NULL


ebird_sampling_density_plot = ebird_sampling_density_df %>%
  ggplot(aes(holc_grade, sampling_density, fill = holc_grade)) +
  geom_col() + 
  scale_fill_manual(values = holc_pal) + 
  theme_bw(16) + 
  theme_classic(16) +
  labs(title='eBird') + 
  theme(legend.position = 'none') + 
  ylab('Sampling density in 1km^2') +
  theme(axis.title.x=element_blank(),
        axis.text.x=element_blank(),
        axis.title.y=element_blank(),
  ) + 
  NULL

ebird_sampling_density_plot / inat_sampling_density_plot / other_sampling_density_plot

ggsave('/Users/diegoellis/Desktop/all_obs_type.png'
       , width = 5
       , height = 9.5
       , dpi = 600
)

# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# [11] Calculate sampling density ####
# --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

# Calculate sampling density:
biodiv_sum = read.table(paste0(outdir, "/R1_biodiv_sum_bird_obs_by_holc_id_1933_2022.csv"), header= T,sep=',')
names(biodiv_sum) <- c('holc_grade','holc_polygon_id', 'Sum', 'City', 'city_state')

sum(biodiv_sum$Sum) # Our paper says 10,043,533 georeferenced ocurrences but I have 10,048,895 here

# names(biodiv_sum) <- c('holc_polygon_id', 'Sum')
# biodiv_sum$holc_grade = substr(sub(".*?_", "", (sub("_.*?", "", sub("_.*?", "", biodiv_sum$holc_polygon_id))) ), 1,1) 
# biodiv_sum[which(biodiv_sum$holc_grade =='2'),]$holc_grade <- 'B'
biodiv_sum = biodiv_sum %>% filter(holc_grade !='E')

sum(biodiv_sum$Sum) # Our paper says 10,043,533 georeferenced ocurrences but I have 10,048,895 here

# Calculate sampling density:
biodiv_sampling_dens = biodiv_sum %>% group_by(holc_grade) %>% dplyr::summarise(n_obs = sum(Sum)) %>% left_join(holc_area, by = 'holc_grade') %>% mutate(sampling_density = n_obs / area_sum)

message(paste0('HOLC grade A has ',
               round( biodiv_sampling_dens[biodiv_sampling_dens$holc_grade =='A',]$sampling_density / 
                        biodiv_sampling_dens[biodiv_sampling_dens$holc_grade =='D',]$sampling_density , 3) ,
               ' higher sampling density than grade D across 195 cities'))

# --- --- --- --- --- --- --- --- --- --- --- --- --- ---
# Now create a master biodiversity dat sheet: ##### 
# --- --- --- --- --- --- --- --- --- --- --- --- --- ---

path_ind = '/Users/diegoellis/projects/Proposals_funding/Yale_internal_grants/Redlining/2022/HOLC_R1/R1_NHB_HOLC/Biodiv_outputs/'
path_ind = '/Users/diegoellis/Desktop/Nature_Human_Behavior/'
# Climate:
climate = read.csv(paste0(path_ind, 'CSV_tables/R1_climatic_data_cities.csv'))
# Completeness:
completeness = read.csv( paste0(path_ind, 'CSV_tables/bird_completeness_HOLC_cities_2022_R1.csv') ) # Only 7665 polygons were calculated:
completeness$City = gsub('/','',completeness$City)
cities_i_want[!cities_i_want %in% unique(completeness$City) ]  # Oklahoma City, Houston, Pawtuket, Providence, San Antonio cant be run for survey completeness
sum(completeness$Records) # We loose allmost a million recordss and i dont know why?
# Load sampling density
biodiv_sum = read.table(paste0(path_ind, "CSV_tables//R1_biodiv_sum_bird_obs_by_holc_id_1933_2022.csv"), header= F,sep=',')

names(biodiv_sum) <- c('holc_grade','holc_polygon_id', 'Sum','City', 'citiy_state')
biodiv_sum$holc_grade = substr(sub(".*?_", "", (sub("_.*?", "", sub("_.*?", "", biodiv_sum$holc_polygon_id))) ), 1,1) 
biodiv_sum[which(biodiv_sum$holc_grade =='2'),]$holc_grade <- 'B'
biodiv_sum = biodiv_sum %>% filter(holc_grade !='E')
biodiv_sum = biodiv_sum %>% filter(holc_grade %in% c('A', 'B', 'C', 'D'))
# Calculate sampling density:
biodiv_sampling_dens = biodiv_sum %>% group_by(holc_grade) %>% dplyr::summarise(n_obs = sum(Sum)) %>% left_join(holc_area, by = 'holc_grade') %>% mutate(sampling_density = n_obs / area_sum)

# Left join and make sure that there is 8494 polygons and then link it back to the 195 cities ! 
completeness %>% group_by(City, holc_grade) %>% summarise(Completeness)

ddply(completeness, 'City', function(x){
  ddply(x, 'holc_grade', function(y){
    mean(y$Completeness, na.rm=T)
  })
})
