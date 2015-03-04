source('0_settings.R')

library(rgdal)
library(rgeos)
library(foreach)
#install.packages("spgrass7", repos="http://R-Forge.R-project.org")
library(spgrass7)

sitecode <- "VOL"

foreach (sitecode=sitecodes) %do% {
    aoi_folder <- file.path(zoi_folder, sitecode, "TEAM_Core")
    aoi <- readOGR(aoi_folder, "Core_Study_Area")

    # Buffer core area sampling polygon by 100 km
    aoi <- gConvexHull(aoi)
    aoi <- spTransform(aoi, CRS(utm_zone(aoi, proj4string=TRUE)))
    aoi <- gBuffer(aoi, width=100000)
    aoi <- spTransform(aoi, CRS("+init=epsg:4326"))

    dem_folder <- file.path(zoi_folder, sitecode, "DEM")
    dem_filename <- file.path(dem_folder, paste0(sitecode, '_dem.tif'))

    # Location of your GRASS installation:
    loc <- initGRASS("C:/Program Files (x86)/GRASS GIS 7.0.0", home=tempdir())
    execGRASS("r.in.gdal", flags="o", parameters=list(input=dem_filename, output="DEM"))
    execGRASS("g.region", parameters=list(raster="DEM"))
    gmeta()

    thresholds <- as.integer(c((10*1e6/(30*30)),
                               100*1e6/(30*30)))
    ids <- letters[1:length(thresholds)]
    # Set a threshold of 10km^2
    streamvecs <- foreach (threshold=thresholds, id=ids) %do% {
        # extract the drainage network:
        execGRASS("r.watershed",
                  flags="overwrite", 
                  parameters=list(elevation="DEM",
                                  stream=paste0("stream_", id), 
                                  basin=paste0("basin_", id), 
                                  memory=2000,
                                  threshold=threshold))

        out <- list()
        # thin the raster map so it can be converted to vectors:
        execGRASS("r.thin", flags="overwrite",
                  parameters=list(input=paste0("stream_", id),
                                  output=paste0("streamt_", id)))
        # convert to vectors:
        execGRASS("r.to.vect", flags="overwrite",
                  parameters=list(input=paste0("streamt_", id),
                                  output=paste0("streamvec_", id),
                                  type="line"))
        out$stream <- readVECT(paste0("streamvec_", id))

        execGRASS("r.thin", flags="overwrite",
                  parameters=list(input=paste0("basin_", id),
                                  output=paste0("basint_", id)))
        execGRASS("r.to.vect", flags="overwrite",
                  parameters=list(input=paste0("basint_", id),
                                  output=paste0("basinvec_", id),
                                  type="line"))
        out$basin <- readVECT(paste0("basinvec_", id))

        return(out)
    }

    plot(streamvecs[1])
    plot(streamvecs[2])

}
