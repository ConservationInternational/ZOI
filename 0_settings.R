###############################################################################
# Load packages (do not modify these lines)
library(teamlucc)

###############################################################################
# General settings (update as necessary)

PLOT_WIDTH <- 6.5
PLOT_HEIGHT <- 6.5
PLOT_DPI <- 300

prefixes <- c('D:/azvoleff/Data', # CI-TEAM
              'H:/Data', # Buffalo drive
              'O:/Data', # Blue drive
              '/localdisk/home/azvoleff/Data') # vertica1
prefix <- prefixes[match(TRUE, unlist(lapply(prefixes, function(x) file_test('-d', x))))]

# Setup input paths
zoi_folder <- file.path(prefix, 'TEAM', 'ZOI_Construction')

# Setup output paths
sites <- read.csv(file.path(prefix, 'TEAM/Sitecode_Key/sitecode_key.csv'))
sites <- sites[sites$sitecode == "VOL", ]
sitecodes <- sites$sitecode

temps <- c('H:/Temp', # Buffalo drive
           'O:/Temp', # Blue drive (HP or thinkpad)
           '/localdisk/home/azvoleff/Temp', # vertica1
           'D:/Temp') # CI-TEAM
temp <- temps[match(TRUE, unlist(lapply(temps, function(x) file_test('-d', x))))]
rasterOptions(tmpdir=temp)

# Specify how many processors to use for parallel processing. On CI-TEAM, this 
# should be set to 6. On your laptop, set it somewhere between 2 and 4.
if (Sys.info()[4] == 'CI-TEAM') {
    n_cpus <- 8
} else if (Sys.info()[4] == 'vertica1.team.sdsc.edu') {
    n_cpus <- 16
} else {
    n_cpus <- 3
}

# Should any existing output files be overwritten as the script runs? If set to 
# FALSE, and there ARE existing files for earlier runs of the script, the 
# script will raise an error and stop running.
overwrite <- TRUE

# Load the DEM extents needed for the auto_setup_dem function
load('dem_extents.RData')
dem_path <- file.path(prefix, 'CGIAR_SRTM', 'Tiles')
dem_extents$filename <- gsub('H:\\\\Data\\\\CGIAR_SRTM', dem_path, dem_extents$filename)
dem_extents$filename <- gsub('\\\\', '/', dem_extents$filename)
