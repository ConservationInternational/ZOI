> library(spgrass6)  
# Location of your GRASS installation:
> loc <- initGRASS("C:/GRASS", home=tempdir())
> loc
# Import the ArcInfo ASCII file to GRASS:
> execGRASS("r.in.gdal", flags="o", parameters=list(input="DEM25m.asc", output="DEM"))
> execGRASS("g.region", parameters=list(rast="DEM"))
> gmeta6()
# extract the drainage network:
> execGRASS("r.watershed", flags="overwrite", parameters=list(elevation="DEM", stream="stream",
threshold=as.integer(50)))
# thin the raster map so it can be converted to vectors:
> execGRASS("r.thin", parameters=list(input="stream", output="streamt"))
# convert to vectors:
> execGRASS("r.to.vect", parameters=list(input="streamt", output="streamt", feature="line"))
> streamt <- readVECT6("streamt")
> plot(streamt)
