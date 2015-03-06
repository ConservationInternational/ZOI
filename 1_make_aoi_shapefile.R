source('0_settings.R')

library(gdalUtils)
library(rgdal)
library(rgeos)
library(foreach)

foreach (sitecode=sitecodes) %do% {
    aoi_folder <- file.path(zoi_folder, sitecode, "TEAM_Core")
    aoi <- readOGR(aoi_folder, "Core_Study_Area")

    # Buffer core area sampling polygon by 100 km
    aoi <- gConvexHull(aoi)
    aoi <- spTransform(aoi, CRS(utm_zone(aoi, proj4string=TRUE)))
    aoi <- gBuffer(aoi, width=100000)
    aoi <- spTransform(aoi, CRS("+init=epsg:4326"))

    dem_folder <- file.path(zoi_folder, sitecode, "DEM")
    if (!file_test('-d', dem_folder)) {
        dir.create(dem_folder)
    }

    setup_zoi_dem(aoi, dem_folder, dem_extents, n_cpus=n_cpus, 
                  overwrite=overwrite)
}

setup_zoi_dem <- function(aoi, output_path, dem_extents, of="GTiff", 
                          ext='tif', n_cpus=1, overwrite=FALSE) {
    if (!file_test("-d", output_path)) {
        stop(paste(output_path, "does not exist"))
    }

    if (length(aoi) > 1) {
        stop('aoi should be a SpatialPolygonsDataFrame of length 1')
    }
    stopifnot(!is.projected(aoi))

    ext <- gsub('^[.]', '', ext)

    if (proj4comp(proj4string(aoi), proj4string(dem_extents[1]))) {
        aoi <- spTransform(aoi, CRS(proj4string(dem_extents[1])))
    } else {
        stop('aoi projection must match projection of dem_extents')
    }

    intersecting <- as.logical(gIntersects(dem_extents, gUnaryUnion(aoi), byid=TRUE))
    if (sum(intersecting) == 0) {
        stop('no intersecting dem extents found')
    } else {
        dem_extents <- dem_extents[intersecting, ]
    }

    dem_list <- dem_extents$filename
    dem_rasts <- lapply(dem_list, raster)

    dem_filename <- file.path(output_path, paste0(sitecode, '_dem.', ext))

    # Verify projections of DEMs match
    dem_prj <- projection(dem_rasts[[1]])
    if (any(lapply(dem_rasts, projection) != dem_prj)) {
        stop("each DEM in dem_list must have the same projection")
    }

    # Calculate minimum bounding box coordinates:
    dem_te <- as.numeric(bbox(aoi))
    to_res <- res(dem_rasts[[1]])

    # Mosaic DEMs, using mosaic_rasters from gdalUtils for speed:
    dem_mosaic <- mosaic_rasters(dem_list, dem_filename, te=dem_te, 
                                 tr=to_res, output_Raster=TRUE, 
                                 multi=TRUE, wo=paste0("NUM_THREADS=", n_cpus), 
                                 overwrite=overwrite, ot='Int16', tap=TRUE)

    # slopeaspect_filename <- file.path(output_path,
    #                                   paste0(sitecode, '_slopeaspect.', ext))
    # # Note that the default output of 'terrain' is in radians
    # slopeaspect <- terrain(dem_mosaic, opt=c('slope', 'aspect'), 
    #                        filename=slopeaspect_filename, overwrite=overwrite)
}
