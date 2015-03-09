source('0_settings.R')

library(gfcanalysis)
library(raster)
library(sp)
library(maptools)
library(rgdal)
library(tools)
library(stringr)
library(rgeos)
library(reshape2)
library(foreach)
library(doParallel)

###############################################################################
# Setup parameters
###############################################################################

overwrite <- TRUE
forest_thresholds <- c(50, 75, 99)
to_utm <- FALSE

# Setup possible locations for data files
prefixes <- c('D:/azvoleff/Data', # CI-TEAM
              'H:/Data', # Buffalo drive
              'O:/Data', # Blue drive
              '/localdisk/home/azvoleff/Data') # vertica1

# Specify data_folder relative to above prefixes
data_folder <- file.path(prefix, 'GFC_Product')

# Setup possible locations for temp files
temps <- c('H:/Temp', # Buffalo drive
           'O:/Temp', # Blue drive (HP or thinkpad)
           '/localdisk/home/azvoleff/Temp', # vertica1
           'D:/Temp') # CI-TEAM

###############################################################################
# Script begins below
###############################################################################

if (to_utm) {
    utm_string <- '_utm'
} else {
    utm_string <- '_wgs84'
}

# Specify how many processors to use for parallel processing. On CI-TEAM, this 
# should be set to 10. On your laptop, set it somewhere between 2 and 4.
if (Sys.info()[4] == 'CI-TEAM') {
    n_cpus <- 9
} else if (Sys.info()[4] == 'vertica1.team.sdsc.edu') {
    n_cpus <- 16
} else {
    n_cpus <- 3
}

prefix <- prefixes[match(TRUE, unlist(lapply(prefixes, function(x) file_test('-d', x))))]

temp <- temps[match(TRUE, unlist(lapply(temps, function(x) file_test('-d', x))))]

cl <- makeCluster(n_cpus)
registerDoParallel(cl)

# Ensure all output_folders exist, to avoid race conditions
dircreates <- foreach (sitecode=sitecodes) %:%
    foreach (forest_threshold=forest_thresholds) %do% {
        this_output_folder <- file.path(prefix, 'TEAM', 'ZOI_Construction', sitecode, 'GFC',
                                   paste0(gsub('_', '', utm_string), '_', 
                                          forest_threshold, 'pct'))
        if (!file_test('-d', this_output_folder)) {
            print(paste(this_output_folder, 'does not exist - creating it'))
            dir.create(this_output_folder)
        } else if (overwrite) {
            warning(paste(this_output_folder, "already exists - existing files will be overwritten"))
        } else {
            stop(paste(this_output_folder, "already exists"))
        }
    return(TRUE)
}

sitecode <- "VOL"
forest_threshold <- 75
foreach (sitecode=sitecodes, .inorder=FALSE,
         .packages=c('gfcanalysis', 'raster', 'sp', 'maptools',
                     'rgdal', 'tools', 'rgeos', 'stringr')) %dopar% {
    aoi_folder <- file.path(zoi_folder, sitecode, "TEAM_Core")
    aoi <- readOGR(aoi_folder, "Core_Study_Area")

    # Buffer core area sampling polygon by 100 km
    aoi <- gConvexHull(aoi)
    aoi <- spTransform(aoi, CRS(utm_zone(aoi, proj4string=TRUE)))
    aoi <- gBuffer(aoi, width=100000)
    if (!to_utm) aoi <- spTransform(aoi, CRS("+init=epsg:4326"))

    raster_tmpdir <- file.path(temp, paste0('raster_',
                               paste(sample(c(letters, 0:9), 15), 
                                     collapse='')))
    dir.create(raster_tmpdir)
    rasterOptions(tmpdir=raster_tmpdir)

    output_folder <- file.path(prefix, 'TEAM', 'ZOI_Construction', sitecode, 'GFC')
    aoi_file <- file.path(output_folder, paste0(sitecode, '_aois', utm_string, 
                                                '.RData'))
    save(aoi, file=aoi_file)

    timestamp()

    tiles <- calc_gfc_tiles(aoi)
    print("Downloading data...")
    download_tiles(tiles, data_folder, first_and_last=FALSE)

    gfc_data_file <- file.path(output_folder,
                               paste0(sitecode, '_gfcextract', utm_string, 
                                      '.tif'))
    if (overwrite || !file.exists(gfc_data_file)) {
        timestamp()
        print("Extracting GFC data...")
        gfc_data <- extract_gfc(aoi, data_folder, to_UTM=to_utm, 
                                filename=gfc_data_file, overwrite=TRUE)
    } else {
        gfc_data <- brick(gfc_data_file)
    }

    watermask <- gfc_data[[5]] == 2
    watermask_file <- file.path(output_folder,
                                paste0(sitecode, '_watermask', utm_string, 
                                       '.tif'))
    watermask <- writeRaster(watermask, file=watermask_file, 
                             overwrite=overwrite)

    foreach (forest_threshold=forest_thresholds) %do% {
        this_output_folder <- file.path(output_folder,
                                        paste0(gsub('_', '', utm_string), '_', 
                                               forest_threshold, 'pct'))
        gfc_thresholded_file <- file.path(this_output_folder,
                                          paste0(sitecode, '_gfcextract', 
                                                 utm_string, '_threshold.tif'))
        if (overwrite || !file.exists(gfc_thresholded_file)) {
            timestamp()
            print("Thresholding GFC data...")
            gfc_thresholded <- threshold_gfc(gfc_data, 
                                             forest_threshold=forest_threshold, 
                                             filename=gfc_thresholded_file,
                                             overwrite=TRUE)
        } else {
            gfc_thresholded <- brick(gfc_thresholded_file)
        }

        gfc_stats_file <- file.path(this_output_folder,
                                    paste0(sitecode, '_gfcextract', utm_string, 
                                           '_stats_loss.csv'))
        if (overwrite || !file.exists(gfc_stats_file)) {
            timestamp()
            print("Generating annual GFC stats...")
            chg_stats <- gfc_stats(aoi, gfc_thresholded)
            write.csv(chg_stats$loss_table, file=gfc_stats_file, row.names=FALSE)
            gfc_gainstats_file <- file.path(this_output_folder,
                                            paste0(sitecode, '_gfcextract', 
                                                   utm_string, '_stats_gain.csv'))
            write.csv(chg_stats$gain_table, file=gfc_gainstats_file, 
                      row.names=FALSE)
        }

        gfc_annual_stack_file <- file.path(this_output_folder, paste0(sitecode, 
        '_gfcextract', utm_string, '_annual.tif'))
        if (overwrite || !file.exists(gfc_annual_stack_file)) {
            timestamp()
            print("Generating annualized GFC stack...")
            gfc_annual_stack <- annual_stack(gfc_thresholded)
            writeRaster(gfc_annual_stack, filename=gfc_annual_stack_file, datatype='INT1U', 
                        overwrite=TRUE)
        } else {
            gfc_annual_stack <- brick(gfc_annual_stack_file)
        }
    }

    removeTmpFiles(h=0)
    unlink(raster_tmpdir)
}

stopCluster(cl)
