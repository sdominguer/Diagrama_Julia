import JLD2
import CSV
import SHA
import DataFrames
import XLSX
import ArchGDAL
import GeoInterface

import SimCCSpro
using TimerOutputs


"""
$(DocumentFunction.documentfunction(loaddata;
maintext="""
SimCCSpro data loader
""",
argtext=Dict("project"=>"SimCCS project [default=`\"ProjectName\"`]",
			"scenario"=>"SimCCS scenario [default=`\"capScenario\"`]"),
keytext=Dict("jld"=>"load inputs from JLD2 file for fast reloading (if already saved) [default=`true`]",
			"intermodal"=>"Wether to load intermodal data",
			"secondOrderDelaunayEdges"=>"Generate 2nd order Delaunay Edges when regenerating the candidate network",
			"crf"=>"Cost reduction factor used to convert to current dollars",
			"numYears"=>"length of the scenario",
			"costDir"=>"directory where the network costs are stored",
			"sourceInputCustomerFilter"=>"A vector of booleans defining whether to include each column in the customer source input shapefile",
			"sinkInputCustomerFilter"=>"A vector of booleans defining whether to include each column in the customer sink input shapefile",
			"candidateNetworkCustomerFilter"=>"A vector of booleans defining whether to include each column in the customer candiate network shapefile",
			"intermodalInputCustomerFilter"=>"A vector of booleans defining whether to include each column in the customer intermodal terminals input shapefile",
			"useSmoothedNetwork"=>"Load the smoothed version of the Candidate Network for the data.")))

Returns:

- SimCCS data structure with all the data

Examples:

```julia
SimCCSpro.loaddata()
SimCCSpro.loaddata("SoutheastUS")
SimCCSpro.loaddata("SoutheastUS", "capScenario")
SimCCSpro.loaddata("SoutheastUS", "capScenario"; jld=false)
```
"""
@inject_timer function loaddata(project::AbstractString="ProjectName", scenario::AbstractString="capScenario"; 
				  jld::Bool=true, 
				  intermodal::Bool=false, 
				  secondOrderDelaunayEdges::Bool=false, 
				  crf::Float64=0.11, 
				  numYears::Int64=30, 
				  costdir::AbstractString="CostNetwork",
				  candidateNetwork::AbstractString="CandidateNetwork",
				  sourceInputCustomerFilter::Vector{Bool}=[true, true, true, true, true, true, true, true, true, true, true, true, true, true, true], 
				  sinkInputCustomerFilter::Vector{Bool}=[true, true, true, true, true, true, true, true, true, true, true], 
				  candidateNetworkCustomerFilter::Vector{Bool}=[true, true, true], 
				  intermodalInputCustomerFilter::Vector{Bool}=[true, true, true],
				  useSmoothedNetwork::Bool=false
				)
	@timeit SimCCSpro.HighLevelTimings() "Load Data" begin		
		gdata = load_costs(project, scenario; jld=jld, intermodal=intermodal, costdir=costdir) # Load costs
		gdata.project = project
		gdata.numYears = numYears
		gdata.interestRate = 0.09
		gdata.crf = crf
		gdata.sourcesSinksWithinCostSurface = true
		gdata.candidateNetworkName = candidateNetwork;  # other functions use this 

		
		load_scenario!(gdata, scenario; intermodal, secondOrderDelaunayEdges, costdir=costdir) # Load scenario
		if intermodal && gdata.sourcesSinksWithinCostSurface # Regenrate candidate graph to connect intermodal terminals to the candidate network
			generateCandidateNetwork!(gdata; intermodal=intermodal, secondOrderDelaunayEdges=secondOrderDelaunayEdges)
		end
	end
	@timeit SimCCSpro.HighLevelTimings() "Create Shapefiles" begin
		# Generate scenario shapefiles if not already exists
		scenarioShapefilesExists = true

		if !isfile(joinpath(SimCCSpro.dir, "Scenarios", scenario, "Shapefiles", "Sources.shp"))
			scenarioShapefilesExists = false
		elseif !isfile(joinpath(SimCCSpro.dir, "Scenarios", scenario, "Shapefiles", "Sinks.shp"))
			scenarioShapefilesExists = false
		elseif !isfile(joinpath(SimCCSpro.dir, "Scenarios", scenario, "Shapefiles", "$(gdata.candidateNetworkName).shp"))
			scenarioShapefilesExists = false
		elseif intermodal && !isfile(joinpath(SimCCSpro.dir, "Scenarios", scenario, "Shapefiles", "Terminals.shp"))
			scenarioShapefilesExists = false
		end

		if !scenarioShapefilesExists
			# println("CREATING SHAPEFILE!")
			generateScenarioShapefiles(gdata; intermodal=intermodal, candidateNetworkFilename=candidateNetwork, sourceInputCustomerFilter=sourceInputCustomerFilter, sinkInputCustomerFilter=sinkInputCustomerFilter, candidateNetworkCustomerFilter=candidateNetworkCustomerFilter, intermodalInputCustomerFilter=intermodalInputCustomerFilter)
		else
			# println("NOT CREATING THE SHAPEFILE!!!!!")
		end

		# create the smoothed network if the original one was correctly created and if the smoothed network isn't there 
		smoothed_network_shp = joinpath(SimCCSpro.dir, "Scenarios", scenario, "Shapefiles", "$(gdata.candidateNetworkName)_S.shp");
		if isfile(joinpath(SimCCSpro.dir, "Scenarios", scenario, "Shapefiles", "$(gdata.candidateNetworkName).shp")) && !isfile(smoothed_network_shp) # _S to indicate the smoothed version
			if useSmoothedNetwork
				# make sure the smoothing parameters match what CostMAPpro does!
				gdata_smoothed = copy(gdata); # need to make a copy to correctly initialize the costs and write it out too
				println("Candidate network name is $(gdata_smoothed.candidateNetworkName)")
				SmoothCandidateNetwork!(gdata_smoothed; 
						λ = 0.5,    # how much it will deviate from the original curve (0.0 means nothing happens, 1.0 is the most extreme movement)
						neighbors=1,   # how many neighbors the smoothing will be based on 
						cellInfitScale = 0.8    # how close to the center will the resulting vertex need to stay to be valid
				);

				# create the customer version of the smoothed shapefile 
				customer_smoothed_network_shp = joinpath(SimCCSpro.dir, "Scenarios", scenario, "Shapefiles", "$(gdata.candidateNetworkName)customer_S.shp");
				candidateNetworkAttrs = getCandidateNetworkAttributes();
				generateFilteredShapefile(smoothed_network_shp, customer_smoothed_network_shp, candidateNetworkAttrs, candidateNetworkCustomerFilter);
			else
				@warn("Not creating the smoothed candidate network anymore.")
			end
		end

		if useSmoothedNetwork
			# this requires re-running some of the loading code but it doesn't take that long 
			gdata.candidateNetworkName = "$(candidateNetwork)_S";
			# does not use the "useSmoothedNetwork" parameter in the call above in case the smoothed network 
			# hasn't been created just yet 
			load_scenario!(gdata, scenario; intermodal, secondOrderDelaunayEdges, costdir=costdir, useSmoothedNetwork=useSmoothedNetwork);
		end
	end

	return gdata
end


"""
Reads .txt file containing wkt string (wkt_info.txt) and converts the string into a proj4 string that is readable by GMT.
Dependent on ArchGDAL for now.

$(DocumentFunction.documentfunction(load_WKT!))
"""
@inject_timer function load_WKT!(gdata::Data; costdir::AbstractString="CostNetwork", filename::AbstractString=joinpath("BaseData", costdir, "wkt_info.txt"))
	filename_JLD2 = joinpath("BaseData", costdir, "wkt_info.jld2")
	
	if isfile(joinpath(SimCCSpro.dir, filename_JLD2))
		@info("Loading Projection info from $(joinpath(SimCCSpro.dir, filename_JLD2)) ...")
		wkt_dict = JLD2.load(joinpath(SimCCSpro.dir, filename_JLD2))
		wkt = wkt_dict["projection"]

		# Convert wkt string to spatial reference system
		wkt = ArchGDAL.importWKT(wkt);
		# Convert SRS to proj4 string
		proj4 = ArchGDAL.toPROJ4(wkt);
		#remove spaces
		proj4 = filter(x->!isspace(x), proj4);

		#Store projection string in gdata
		gdata.projection = proj4

	elseif isfile(joinpath(SimCCSpro.dir, filename))
		@info("Loading Projection info from $(joinpath(SimCCSpro.dir, filename)) ...")
		f = open(joinpath(SimCCSpro.dir, filename), "r")
		wkt=""
		# save lines as string
		for lines in readlines(f)
			wkt=wkt*chomp(lines);
		end
		close(f)

		# Convert wkt string to spatial reference system
		wkt = ArchGDAL.importWKT(wkt);
		# Convert SRS to proj4 string
		proj4 = ArchGDAL.toPROJ4(wkt);
		#remove spaces
		proj4 = filter(x->!isspace(x), proj4);

		#Store projection string in gdata
		gdata.projection = proj4
	else
		@info("No WKT file found. Using Albers Equal Area projection")
		#If no wkt file, use albers conic equal area projection
		gdata.projection ="+proj=aea+lat_0=23+lon_0=-96+lat_1=29.5+lat_2=45.5"
	end

	return nothing
end

"""
$(DocumentFunction.documentfunction(load_costs;
maintext="""
SimCCSpro cost loader
""",
argtext=Dict("project"=>"SimCCS project name"),
keytext=Dict("jld"=>"load inputs from JLD2 file for fast reloading (if already saved) [default=`true`]")))

Returns:

- SimCCS data structure with all the data

Examples:

```julia
SimCCSpro.loadcosts()
SimCCSpro.loadcosts("SoutheastUS")
SimCCSpro.loadcosts("SoutheastUS"; jld=false)
```
"""
@inject_timer function load_costs(project::AbstractString="ProjectName", scenario::AbstractString=gdata.scenario; jld::Bool=true, intermodal::Bool=false, costdir::AbstractString="CostNetwork", directory::AbstractString=joinpath(SimCCSpro.dir_write, "BaseData", costdir), filename::AbstractString=joinpath(directory, project * ".jld2"))
	gdata = Data()
	gdata.carbonTax = 0
	gdata.carbonTaxCreditSaline = 85
	gdata.carbonTaxCreditOnG = 60
	gdata_cost_fields = [:allNodes, :activeNodes, :height, :width, :xllCorner, :yllCorner, :cellSize, :projectionVersion, :rightOfWayCosts, :constructionCosts, :routingCosts, :cellneighbors] # Cost fields for data loading/saving
	if jld && isfile(filename)
		# If the jld flag is set and the .jld2 file exists, load the cost data from the .jld2 file
		@info("Loading BaseData from $filename ...")
		gdata_dict = JLD2.load(filename)
		dict_to_struct!(gdata, gdata_dict)
	else
		# If the jld flag is not set or the .jld2 file does not exist, load the cost data from the text/csv files and save it to a .jld2 file so it will load faster next time
		load_constructionCosts!(gdata; costdir=costdir)
		load_rightOfWayCosts!(gdata; costdir=costdir )
		load_routingCosts!(gdata; costdir=costdir)

		gdata_dict = SimCCSpro.struct_to_dict(gdata, gdata_cost_fields)
		@info("Saving BaseData in $filename ...")
		if !isdir(directory)
			mkpath(directory)
		end
		JLD2.save(filename, gdata_dict)
	end

	return gdata
end

"""
$(DocumentFunction.documentfunction(load_constructionCosts!;
maintext="""
Load construction costs
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data")))

Returns:

- nothing

Examples:

```julia
SimCCSpro.load_constructionCosts!(gdata)
```
"""
@inject_timer function load_constructionCosts!(gdata::Data; costdir::AbstractString="CostNetwork", filename::AbstractString=joinpath("BaseData", costdir, "Cost Weights.txt")) # TODO  / To discuss- Rename as load_constructioncosts?
	filename_JLD2 =joinpath("BaseData", costdir, "CostWeights.jld2")
	
	if isfile(joinpath(SimCCSpro.dir, filename_JLD2))
		@info("Loading Construction Costs from $filename_JLD2 ...")
		costsurface_dict = JLD2.load(joinpath(SimCCSpro.dir, filename_JLD2))

		# gdata.width = costsurface_dict["numCols"]
		# gdata.height = costsurface_dict["numRows"]

		if haskey(costsurface_dict, "numRows")
			gdata.height = costsurface_dict["numRows"];
		elseif haskey(costsurface_dict, "geometry")
			gdata.height = costsurface_dict["geometry"]["numRows"];
		else
			@error("Could not retrieve numRows from network file $(joinpath(SimCCSpro.dir, filename_JLD2))")
		end
		if haskey(costsurface_dict, "numCols")
			gdata.width = costsurface_dict["numCols"];
		elseif haskey(costsurface_dict, "geometry")
			gdata.width = costsurface_dict["geometry"]["numCols"];
		else
			@error("Could not retrieve numCols from network file $(joinpath(SimCCSpro.dir, filename_JLD2))")
		end

		gdata.allNodes = gdata.width * gdata.height
		gdata.activeNodes = gdata.allNodes

		# geotransform[1] x-coordinate of the upper-left corner of the upper-left pixel.
		# geotransform[2] w-e pixel resolution / pixel width.
		# geotransform[3] row rotation (typically zero).
		# geotransform[4] y-coordinate of the upper-left corner of the upper-left pixel.
		# geotransform[5] column rotation (typically zero). 
		# geotransform[6] n-s pixel resolution / pixel height (negative value for a north-up image).

		gdata.xllCorner = costsurface_dict["geotransform"][1]
		gdata.yllCorner = costsurface_dict["geotransform"][4] +costsurface_dict["geotransform"][6]*gdata.height
		gdata.cellSize = costsurface_dict["geotransform"][2]

		# Check whether the x and y coordinates for the lower left corner are within the realm of potential decimal degree coordinates
		if (
			(gdata.xllCorner > 180 || gdata.xllCorner < -180) ||
			(gdata.yllCorner > 90 || gdata.yllCorner < -90)
		)
			gdata.projectionVersion = 2
		else
			gdata.projectionVersion = 1
		end

		costData = costsurface_dict["data"]
		gdata.constructionCosts, gdata.cellneighbors = load_costs_cells_JLD2(costData, gdata.height, gdata.width)

		gdata.input_constructioncosts = DataInput()
		gdata.input_constructioncosts.dir = SimCCSpro.dir
		gdata.input_constructioncosts.file = filename_JLD2
		gdata.input_constructioncosts.hash = createhash(gdata.constructionCosts)
		gdata.input_constructioncosts.date = Dates.unix2datetime(mtime(joinpath(SimCCSpro.dir, filename_JLD2)))
		@info("$(length(gdata.constructionCosts)) Construction Costs loaded.")

	elseif	isfile(joinpath(SimCCSpro.dir, filename)) # Check for the existence of the ConstructionCosts file
		@info("Loading Construction Costs from $(joinpath(SimCCSpro.dir, filename)) ...")
		gfile = open(joinpath(SimCCSpro.dir, filename))
		# Load the metadata from the beginning of the construction costs file
		line = readline(gfile)
		gdata.allNodes = parse(Int64, last(split(line)))
		line = readline(gfile)
		gdata.activeNodes = parse(Int64, last(split(line)))
		line = readline(gfile)
		gdata.width = parse(Int64, last(split(line)))
		line = readline(gfile)
		gdata.height = parse(Int64, last(split(line)))
		line = readline(gfile)
		gdata.xllCorner = parse(Float64, last(split(line)))
		line = readline(gfile)
		gdata.yllCorner = parse(Float64, last(split(line)))
		line = readline(gfile)
		gdata.cellSize = parse(Float64, last(split(line)))
		# Check whether the x and y coordinates for the lower left corner are within the realm of potential decimal degree coordinates
		if (
			(gdata.xllCorner > 180 || gdata.xllCorner < -180) ||
			(gdata.yllCorner > 90 || gdata.yllCorner < -90)
		)
			gdata.projectionVersion = 2
		# Otherwise, assume ?
		# TODO ask about projection system assumptions
		else
			gdata.projectionVersion = 1
		end
		# Skip the NODATA_value
		line = readline(gfile)
		# Done with the metadata, load the cell data
		gdata.constructionCosts, gdata.cellneighbors = load_costs_cells(gdata, gfile)
		close(gfile)
		gdata.input_constructioncosts = DataInput()
		gdata.input_constructioncosts.dir = SimCCSpro.dir
		gdata.input_constructioncosts.file = filename
		gdata.input_constructioncosts.hash = createhash(gdata.constructionCosts)
		gdata.input_constructioncosts.date = Dates.unix2datetime(mtime(joinpath(SimCCSpro.dir, filename)))
		@info("$(length(gdata.constructionCosts)) Construction Costs loaded.")
	else
		# If the ConstructionCosts file does not exist, throw the appropriate error messages
		@error("File $(joinpath(SimCCSpro.dir, filename_JLD2)) or $(joinpath(SimCCSpro.dir, filename)) does not exist!")
		throw("Loading Construction Costs from $(joinpath(SimCCSpro.dir, filename_JLD2)) or $(joinpath(SimCCSpro.dir, filename)) failed!")
		throw("Incorrect input data!")
	end
	return nothing
end

"""
$(DocumentFunction.documentfunction(load_rightOfWayCosts!;
maintext="""
Load RightOfWay costs
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data")))

Returns:

- nothing

Examples:

```julia
SimCCSpro.load_rightOfWayCosts!(gdata)
```
"""
@inject_timer function load_rightOfWayCosts!(gdata::Data; costdir::AbstractString="CostNetwork", filename::AbstractString=joinpath("BaseData", costdir, "RightOfWay Costs.txt"))	
	if isfile(joinpath(SimCCSpro.dir, filename))# Check for the existence of the RightOfWay Costs file
		@info("Loading RightOfWay Costs from $(joinpath(SimCCSpro.dir, filename)) ...")
		gfile = open(joinpath(SimCCSpro.dir, filename))
		# Skip the metadata at the beginning of the right of way costs file. Assuming it's the same as what was loaded from the construction costs file
		for i = 1:8
			readline(gfile)
		end
		# Load the cell data
		gdata.rightOfWayCosts, cellneighbors_new = load_costs_cells(gdata, gfile)
		close(gfile)
		@info("$(length(gdata.rightOfWayCosts)) RightOfWay Costs loaded.")
		gdata.input_rightofwaycosts = DataInput()
		gdata.input_rightofwaycosts.dir = SimCCSpro.dir
		gdata.input_rightofwaycosts.file = filename
		gdata.input_rightofwaycosts.hash = createhash(gdata.rightOfWayCosts)
		gdata.input_rightofwaycosts.date = Dates.unix2datetime(mtime(joinpath(SimCCSpro.dir, filename)))
		# Check that the cell neighbors are identical to those loaded from the construction costs file. If not, throw the appropriate error message.
		if cellneighbors_new != gdata.cellneighbors
			@error(
				"Cell Neighbors in $(joinpath(SimCCSpro.dir, filename)) do not match the cell neighbors in the construction cost file!"
			)
			throw("Incorrect input data!")
		end
	else
		# If the RightOfWay Costs file does not exist, create an empty matrix for the right of way costs.
		@warn("File $(joinpath(SimCCSpro.dir, filename)) does not exist!")
		@warn("No RightOfWay file found!")
		gdata.rightOfWayCosts = Matrix{Float64}(undef, 0, 0)
	end
	return nothing
end

"""
$(DocumentFunction.documentfunction(load_routingCosts!;
maintext="""
Load Routing costs
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data")))

Returns:

- nothing

Examples:

```julia
SimCCSpro.load_routingCosts!(gdata)
SimCCSpro.load_routingCosts!(gdata, "SoutheastUS")
```
"""
@inject_timer function load_routingCosts!(gdata::Data; costdir::AbstractString="CostNetwork", filename::AbstractString=joinpath("BaseData", costdir, "Routing Weights.txt")) # TODO / To discuss - Rename as load_RoutingWeights?	
	filename_JLD2 =joinpath("BaseData", costdir, "RoutingWeights.jld2")
	
	if isfile(joinpath(SimCCSpro.dir, filename_JLD2))
		@info("Loading Routing Costs from $filename_JLD2 ...")
		costsurface_dict = JLD2.load(joinpath(SimCCSpro.dir, filename_JLD2))

		costData = costsurface_dict["data"]
		gdata.routingCosts, cellneighbors_new = load_costs_cells_JLD2(costData, gdata.height, gdata.width)

		gdata.input_routingcosts = DataInput()
		gdata.input_routingcosts.dir = SimCCSpro.dir
		gdata.input_routingcosts.file = filename_JLD2
		gdata.input_routingcosts.hash = createhash(gdata.routingCosts)
		gdata.input_routingcosts.date = Dates.unix2datetime(mtime(joinpath(SimCCSpro.dir, filename_JLD2)))

		# Check that the cell neighbors are identical to those loaded from the construction costs file. If not, throw the appropriate error message.
		if cellneighbors_new != gdata.cellneighbors
			@error("Cell Neighbors in $(joinpath(SimCCSpro.dir, filename_JLD)) do not match the cell neighbors in CostWeights.JLD2")
			throw("Incorrect input data!")
		end
	elseif isfile(joinpath(SimCCSpro.dir, filename)) # Check for the existence of the Routing Weights file
		@info("Loading Routing Costs from $(joinpath(SimCCSpro.dir, filename)) ...")
		gfile = open(joinpath(SimCCSpro.dir, filename))
		# Skip the metadata at the beginning of the right of way costs file. Assuming it's the same as what was loaded from the construction costs file
		for i = 1:8
			readline(gfile)
		end
		# Load the cell data
		gdata.routingCosts, cellneighbors_new = load_costs_cells(gdata, gfile)
		close(gfile)
		@info("$(length(gdata.routingCosts)) Routing Costs loaded.")
		gdata.input_routingcosts = DataInput()
		gdata.input_routingcosts.dir = SimCCSpro.dir
		gdata.input_routingcosts.file = filename
		gdata.input_routingcosts.hash = createhash(gdata.routingCosts)
		gdata.input_routingcosts.date = Dates.unix2datetime(mtime(joinpath(SimCCSpro.dir, filename)))
		
		# Check that the cell neighbors are identical to those loaded from the construction costs file. If not, throw the appropriate error message.
		if cellneighbors_new != gdata.cellneighbors
			@error("Cell Neighbors in $(joinpath(SimCCSpro.dir, filename)) do not match the cell neighbors in $filename_cost!")
			throw("Incorrect input data!")
		end
	else
		# If the Routing Weights file does not exist, throw the appropriate warnings and use the costs from Cost Weights for routing.
		@warn("File $(joinpath(SimCCSpro.dir, filename_JLD)) or $(joinpath(SimCCSpro.dir, filename)) does not exist!")
		@warn("No Routing Costs file found! Using Construction Costs for routing!")
		gdata.routingCosts = gdata.constructionCosts
		gdata.input_routingcosts = DataInput()
		gdata.input_routingcosts.dir = gdata.input_constructioncosts.dir
		gdata.input_routingcosts.file = gdata.input_constructioncosts.file
		gdata.input_routingcosts.hash = gdata.input_constructioncosts.hash
		gdata.input_routingcosts.date = gdata.input_constructioncosts.date
	end
	return nothing
end

"""
$(DocumentFunction.documentfunction(load_scenario!;
maintext="""
Load SimCCS scenario
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"scenario"=>"SimCCS scenario [default=`\"capScenario\"`]")))

Returns:

- nothing

Examples:

```julia
SimCCSpro.load_scenario!(gdata)
SimCCSpro.load_scenario!(gdata, "SoutheastUS")
SimCCSpro.load_scenario!(gdata, "SoutheastUS", "capScenario")
```
"""
@inject_timer function load_scenario!(gdata::Data, 
	                    scenario::AbstractString="capScenario"; 
						intermodal::Bool=false, 
						secondOrderDelaunayEdges::Bool=false, 
						costdir::AbstractString="CostNetwork",
						useSmoothedNetwork::Bool=false
						)
	gdata.scenario = scenario
	load_WKT!(gdata, costdir=costdir)

	if intermodal # Load the intermodal terminals and shipping costs
		load_terminal!(gdata, scenario)
		load_shippingCost!(gdata, scenario)
	end

	load_sources!(gdata)
	load_sinks!(gdata)

	loadTransport!(gdata)

	# If network_metadata.csv file exist and delaunayOrder in the file does not match secondOrderDelaunayEdges,
	# delete the DelaunayPaths.txt and CandidateNetwork.txt files so that they will be regenerated.
	checkNetworkMetadata(gdata, secondOrderDelaunayEdges)
	
	# Check to see whether all sources, sinks and terminals are within the cost surface
	gdata.sourcesSinksWithinCostSurface = isSourcesSinksWithinCostSurface(gdata, intermodal=intermodal)

	if gdata.sourcesSinksWithinCostSurface
		loadDelaunayPairs!(gdata; intermodal, secondOrderDelaunayEdges=secondOrderDelaunayEdges)

		# if it's a custom Candidate Network and that file isn't created yet, then first load 
		# the default one (which must be there to run this function), apply changes to it, write it back, and then set its name
		customCandidateNetwork = gdata.candidateNetworkName != "CandidateNetwork"
		# defaultCandidateNetworkPath = joinpath(SimCCSpro.dir, "DataSets", dataset, "Scenarios", scenario, "Network", "CandidateNetwork", "CandidateNetwork.txt");
		customCandidateNetworkPath = joinpath(SimCCSpro.dir, "Scenarios", gdata.scenario, "Network", "CandidateNetwork", "$(gdata.candidateNetworkName).txt");
		customEditsPath = joinpath(SimCCSpro.dir, "Scenarios", gdata.scenario, "Network", "CandidateNetwork", "$(gdata.candidateNetworkName).csv");

		if customCandidateNetwork
			if !isfile(customCandidateNetworkPath)

				if !isfile(customEditsPath)
					errMsg = "Custom edits file does not exist for the custom Candidate Network: $(customEditsPath)";
					@error(errMsg);
					throw(errMsg); # just error out since it cannot complete the run/loading process without it
				end

				# compare the CandidateNetwork to the edits and then re-create it if needed 
				if isfile(customCandidateNetworkPath) && isfile(customEditsPath)
					editFileInfo = stat(customEditsPath);
					customCandidateNetworkInfo = stat(customCandidateNetworkPath);
					if editFileInfo.mtime > customCandidateNetworkInfo.mtime
						# edit file is newer, so delete the associated text file and the shapefile 
						# delete the custom candidate network path here 
						@info("Recreating the Candidate Network since the edits file is newer than the CandidateNetwork text file.");
						if isfile(customCandidateNetworkPath)
							rm(customCandidateNetworkPath);
						end

						# delete the shapefile 
						files = [];
						ArchGDAL.read(input_shapefile) do input_dataset
							for file=ArchGDAL.filelist(input_dataset);
								push!(files, file);
							end
						end
						for file=files
							if isfile(file)
								rm(file); # need to delete here so it isn't being read
							end
						end
					end
				end

				# load the default one then modify it via the edits file 
				customName = gdata.candidateNetworkName; # store for later
				gdata.candidateNetworkName = "CandidateNetwork";  # loadCandidateNetwork! uses this variable to find the file
				loadCandidateNetwork!(gdata, secondOrderDelaunayEdges=secondOrderDelaunayEdges, useSmoothedNetwork=useSmoothedNetwork);

				# make modifications 
				edits = readCandidateNetworkDiffFile(customEditsPath);
				applyCandidateNetworkDiffs(gdata, edits);
				gdata.candidateNetworkName = customName;

				# write back the modified file 
				SimCCSpro.saveCandidateNetwork(gdata);
			else
				# loading the candidate network file 
				loadCandidateNetwork!(gdata, secondOrderDelaunayEdges=secondOrderDelaunayEdges, useSmoothedNetwork=useSmoothedNetwork);
			end
		else
			loadCandidateNetwork!(gdata, secondOrderDelaunayEdges=secondOrderDelaunayEdges, useSmoothedNetwork=useSmoothedNetwork);
		end
	else
		@error("Delaunay and Candidate Network not loaded due to at least one source or sink not on cost surface")
	end
	
	# TODO loadTimeConfiguration
	# TODO loadCapTargetConfiguration
	return nothing
end

"""
$(DocumentFunction.documentfunction(checkNetworkMetadata;
maintext="""
Check for NetworkMetadata file
If network_metadata.csv file exist and delaunayOrder in the file does not match secondOrderDelaunayEdges,
delete the DelaunayPaths.txt, CandidateNetwork.txt and CandidateNetwork.shp files so that they will be regenerated.
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"secondOrderDelaunayEdges"=>"Flag indicate whether second order delaunay edges is true")))

Returns:

- nothing

Examples:

```julia
SimCCSpro.checkNetworkMetadata(gdata, secondordOrderDelaunayEdges)
```
"""
@inject_timer function checkNetworkMetadata(gdata::Data, secondOrderDelaunayEdges::Bool=false)
	if isfile(joinpath(SimCCSpro.dir, "Scenarios", gdata.scenario, "Network", "network_metadata.csv"))
		deleteFiles = false
		networkMetadataDf = CSV.read(joinpath(SimCCSpro.dir, "Scenarios", gdata.scenario, "Network", "network_metadata.csv"), DataFrames.DataFrame, header=false)
		for row in eachrow(networkMetadataDf)
			col1Value = row.Column1
			col2Value = row.Column2

			if (col1Value == "DelaunayOrder")
				if (col2Value == "1") && secondOrderDelaunayEdges
					deleteFiles = true
				elseif (col2Value == "2") && !secondOrderDelaunayEdges
					deleteFiles = true
				end
				break
			end
		end
		
		if deleteFiles
			if isfile(joinpath(SimCCSpro.dir, "Scenarios", gdata.scenario, "Network", "DelaunayNetwork", "DelaunayPaths.txt"))
				@info("Deleting existing DelaunayNetwork.txt")
				rm(joinpath(SimCCSpro.dir, "Scenarios", gdata.scenario, "Network", "DelaunayNetwork", "DelaunayPaths.txt"))
			end

			if isfile(joinpath(SimCCSpro.dir, "Scenarios", gdata.scenario, "Network", "CandidateNetwork", "CandidateNetwork.txt"))
				@info("Deleting existing CandidateNetwork.txt")
				rm(joinpath(SimCCSpro.dir, "Scenarios", gdata.scenario, "Network", "CandidateNetwork", "CandidateNetwork.txt"))
			end

			if isfile(joinpath(SimCCSpro.dir, "Scenarios", gdata.scenario, "Shapefiles", "CandidateNetwork.shp"))
				@info("Deleting existing CandidateNetwork.shp")
				rm(joinpath(SimCCSpro.dir, "Scenarios", gdata.scenario, "Shapefiles", "CandidateNetwork.shp"))
			end
		end
	end
end



@inject_timer function load_sources!(gdata::Data, scenario::AbstractString=gdata.scenario; filename::AbstractString=joinpath("Scenarios", scenario, "Sources.csv"))
	try
		if isfile(joinpath(SimCCSpro.dir, filename)) # Check for the existence of the Sources file
			@info("Loading Sources from $(joinpath(SimCCSpro.dir, filename)) ...")
			sourceDf = CSV.read(joinpath(SimCCSpro.dir, filename), DataFrames.DataFrame)

			sources = Vector{Source}(undef, 0)

			for row in eachrow(sourceDf)

				# Create a new Source struct
				source = Source()
				
				# Load data from the row into the appropriate variables of the Source struct
				source.co2ncordId = string(row["Co2ncordId"])
				source.facilityId = string(row["FacilityId"])
				source.fac_name = string(row["Fac_name"])
				source.frs_id = string(row["FRS_Id"])
				source.state = string(row["State"])
				source.county = string(row["County"])
				source.city = string(row["City"])
				source.address = string(row["Address"])
				source.x_lon = row["X_lon"]
				source.y_lat = row["Y_lat"]

				# Find the cell number where the source is located
				source.cellNum = getCellNum(gdata, source.y_lat, source.x_lon)

				source.primary = string(row["Primary"])
				source.secondary = string(row["Secondary"])
				source.cap_stream = string(row["Cap_stream"])
				source.capturable = row["Capturable"]
				source.cap_u_cost = row["Cap_u_cost"]
				source.filterValue = string(row["FilterValue"])
				source.filterText = string(row["FilterText"])
				
				# Add the source to the vector of sources
				push!(sources, source)
			end
			@info("$(length(sources)) sources loaded.")
			# Load the sources vector into the data structure
			gdata.sources = sources
			gdata.sources_select = trues(length(sources))
			gdata.input_sources = DataInput()
			gdata.input_sources.dir = SimCCSpro.dir
			gdata.input_sources.file = filename
			gdata.input_sources.hash = createhash(gdata.sources)
			gdata.input_sources.date = Dates.unix2datetime(mtime(joinpath(SimCCSpro.dir, filename)))
		else
			# If the Sources file does not exist, throw the appropriate error messages
			@warn("File $(joinpath(SimCCSpro.dir, filename)) does not exist!")
			@error("No Source file found!")
		end
	
	catch err
		@error(err)
		return nothing
	end

	return nothing
end



@inject_timer function load_sinks!(gdata::Data, scenario::AbstractString=gdata.scenario; filename::AbstractString=joinpath("Scenarios", scenario, "Sinks.csv"))
	try
		if isfile(joinpath(SimCCSpro.dir, filename)) # Check for the existence of the Sources file
			@info("Loading Sinks from $(joinpath(SimCCSpro.dir, filename)) ...")
			sinkDf = CSV.read(joinpath(SimCCSpro.dir, filename), DataFrames.DataFrame)

			sinks = Vector{Sink}(undef, 0)

			for row in eachrow(sinkDf)

				# Create a new Sink struct
				sink = Sink()
				
				# Load data from the row into the appropriate variables of the Sink struct
				sink.sco2tId = string(row["Sco2tId"])
				sink.bg_id = row["BG_ID"]
				sink.form = string(row["Form"])
				sink.land = string(row["Land"])
				sink.stg_cap = row["Stg_cap"]
				sink.stg_u_cost = row["Stg_u_cost"]
				sink.stg_credit = row["Stg_credit"]
				sink.x_lon = row["X_lon"]
				sink.y_lat = row["Y_lat"]
				sink.cap_rank = row["Cap_Rank"]
				sink.cos_rank = row["Cos_Rank"]

				# Find the cell number where the sink is located
				sink.cellNum = getCellNum(gdata, sink.y_lat, sink.x_lon)

				sink.filterValue = string(row["FilterValue"])
				sink.filterText = string(row["FilterText"])

				# Add the source to the vector of sources
				push!(sinks, sink)
			end
			
			# Load the Sinks vector into the data structure
			@info("$(length(sinks)) sinks loaded.")
			gdata.sinks = sinks
			gdata.sinks_select = trues(length(sinks))
			gdata.input_sinks = DataInput()
			gdata.input_sinks.dir = SimCCSpro.dir
			gdata.input_sinks.file = filename
			gdata.input_sinks.hash = createhash(gdata.sinks)
			gdata.input_sinks.date = Dates.unix2datetime(mtime(joinpath(SimCCSpro.dir, filename)))
		else
			# If the Sources file does not exist, throw the appropriate error messages
			@warn("File $(joinpath(SimCCSpro.dir, filename)) does not exist!")
			@error("No Source file found!")
		end
	
	catch err
		@error(err)
		return nothing
	end

	return nothing
end

"""
$(DocumentFunction.documentfunction(loadTransport!;
maintext="""
Load Transport
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"filename"=>"Input file name")))

Returns:

- nothing

Examples:

```julia
SimCCSpro.loadTransport!(gdata, "Linear.txt")
```
"""
@inject_timer function loadTransport!(gdata::Data, scenario::AbstractString=gdata.scenario; filename::AbstractString=joinpath("Scenarios", scenario, "Transport", "Linear.txt"))
	filename = joinpath("Scenarios", scenario, "Linear.txt")
	
	if isfile(joinpath(SimCCSpro.dir, filename)) # Check for the existence of the Linear file
		@info("Loading Transport from $(joinpath(SimCCSpro.dir, filename)) ...")
		gfile = open(joinpath(SimCCSpro.dir, filename))
		# Skip the header row
		readline(gfile)
		linearComponents = Vector{LinearComponent}()
		# Iterate through the remaining lines of the Linear file
		while !eof(gfile)
			line = readline(gfile)
			elements = split(line)
			lc = LinearComponent()
			lc.conSlope = parse(Float64, elements[2])
			lc.conIntercept = parse(Float64, elements[3])
			if length(elements) > 3
				lc.rowSlope = parse(Float64, elements[4])
				lc.rowIntercept = parse(Float64, elements[5])
			end
			push!(linearComponents, lc)
		end
		close(gfile)
		# Load the sources vector into the data struct
		gdata.linearComponents = linearComponents
		@info("$(length(linearComponents)) Transports loaded.")
		gdata.input_transport = DataInput()
		gdata.input_transport.dir = SimCCSpro.dir
		gdata.input_transport.file = filename
		gdata.input_transport.hash = createhash(gdata.linearComponents)
		gdata.input_transport.date = Dates.unix2datetime(mtime(joinpath(SimCCSpro.dir, filename)))

		# Define maximum capacities for each linear function defining pipeline size and cost
		for i = eachindex(linearComponents)
			# For the largest pipeline size function maxCap is the largest reasonable size
			# CPLEX does not do well with infinity here
			# maxCap is smaller of:
			# the total production rate of all sources
			# the total capacity of all sinks divided by the number of years
			maxSource = 0.0

			# Total the production rate for all sources
			for src in gdata.sources
				maxSource += maximum(src.capturable)
			end
			maxSink = 0.0
			# Total the capacity divided by the number of years in the analysis for all sinks
			for snk in gdata.sinks
				maxSink += snk.stg_cap / gdata.numYears
			end

			# Take the lesser of total production or sink capacities divided by years
			maxCap = min(maxSource, maxSink)

			# For all linear functions other than the largest, the maximum capacity is point where the two linear functions cross
			if i < length(linearComponents)
				# Add the construction and right-of-way slopes and intercepts for each linearComponent
				slope1 = linearComponents[i].conSlope + linearComponents[i].rowSlope
				intercept1 = linearComponents[i].conIntercept + linearComponents[i].rowIntercept
				slope2 = linearComponents[i+1].conSlope + linearComponents[i+1].rowSlope
				intercept2 = linearComponents[i+1].conIntercept + linearComponents[i+1].rowIntercept
				# Find the crossover point
				maxCap = (intercept2 - intercept1) / (slope1 - slope2)
			end
			# Save maxCap into the data struct
			gdata.linearComponents[i].maxCapacity = maxCap
		end
	else
		# If the Linear.txt file does not exist, throw the appropriate error messages
		@warn("File $(joinpath(SimCCSpro.dir, filename)) does not exist!")
		@error("No Transport file found!")
	end
	return nothing
end

"""
$(DocumentFunction.documentfunction(loadCandidateNetwork!;
maintext="""
Load Candidate Graph
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"filename"=>"Input file name")))

Returns:

- nothing

Examples:

```julia
SimCCSpro.loadCandidateNetwork!(gdata, "CandidateNetwork.txt")
```
"""
@inject_timer function loadCandidateNetwork!(gdata::Data, scenario::AbstractString=gdata.scenario;
		filename::AbstractString=joinpath("Scenarios", scenario, "Network", "CandidateNetwork", "$(gdata.candidateNetworkName).txt"), 
		secondOrderDelaunayEdges::Bool=false,
		useSmoothedNetwork::Bool=false)
	
	if isfile(joinpath(SimCCSpro.dir, filename)) # Check for the existence of the CandidateNetwork.txt file
		@info("Loading Candidate Graph from $(joinpath(SimCCSpro.dir, filename)) ...")
		gfile = open(joinpath(SimCCSpro.dir, filename))
		# Skip the header row
		readline(gfile)
		# Set up a vector to hold the vertices
		vertices = Vector{Int64}()
		# Set up dictionaries to hold the edges
		gdata.graphEdgeCosts = Dict{Edge, Float64}()
		gdata.graphEdgeConstructionCosts = Dict{Edge, Vector{Int64}}()
		gdata.graphEdgeRightOfWayCosts = Dict{Edge, Float64}()
		gdata.graphEdgeRoutes = Dict{Edge, Float64}()
		gdata.graphEdgeLengths = Dict{Edge, Float64}()

		smoothedGeoms = Dict{Edge, ArchGDAL.IGeometry}();
		if useSmoothedNetwork
			smoothed_network_shp = joinpath(SimCCSpro.dir, "Scenarios", scenario, "Shapefiles", "$(gdata.candidateNetworkName).shp");
			if !endswith(smoothed_network_shp, "_S.shp")
				@warn("Hey, was the candidateNetworkName correctly updated in gdata after smoothing? It is $(gdata.candidateNetworkName) and about to load the smoothed geometry (maybe not?)");
			end
			smoothedGeoms = LoadGeometriesFromCandidateNetworkShapefile(smoothed_network_shp);
		end

		# Iterate through the remaining lines of the CandidateNetwork file
		while !eof(gfile)
			line = readline(gfile)
			elements = split(line)
			v1 = parse(Int64, elements[1])
			v2 = parse(Int64, elements[2])
			push!(vertices, v1)
			push!(vertices, v2)
			e = Edge(v1, v2)
			# Load the edge attributes into the data struct
			push!(gdata.graphEdgeCosts, e=>parse(Float64, elements[3]))
			push!(gdata.graphEdgeConstructionCosts, e=>parse(Float64, elements[4]))
			push!(gdata.graphEdgeRightOfWayCosts, e=>parse(Float64, elements[5]))
			# Load the routes between vertices into the data struct as an array of cell numbers
			push!(gdata.graphEdgeRoutes, e=>parse.(Int64, elements[6:end]))

			# retrieve the smoothed length if using the smoothed network, otherwise can just 
			# use the normal grid-aligned path length 
			if useSmoothedNetwork
				geom = smoothedGeoms[e];
				points = GeoInterface.coordinates(geom);
				npoints = Base.length(points);
				length = 0.0;
				# calculate length like this for consistency with the smoothing code

				# proj_string = "-J"*gdata.projection*" -C"
				
				xlocs = [p[1] for p=points];
				ylocs = [p[2] for p=points];
				
				# the coordinates are already in lat/long (NAD1983)
				# calling GMT.mapproject once here instead of twice for each point pair 
				# points_projected = GMT.mapproject(proj_string, [xlocs ylocs]);  ## lat, long
				points_projected_gmtdata = projectLatLon(ylocs, xlocs, gdata.projection);
				points_projected_matrix = points_projected_gmtdata[:,:]; 
				points_projected =  [ [points_projected_matrix[i,1], points_projected_matrix[i,2]] for i=1:size(points_projected_matrix)[1] ];
	
				for j=2:npoints
					projPoint1 = points_projected[j-1];
					projPoint2 = points_projected[j];
					lenDiffX = projPoint2[1] - projPoint1[1];
					lenDiffY = projPoint2[2] - projPoint1[2];
					seglen = sqrt( lenDiffX*lenDiffX + lenDiffY*lenDiffY )/1000.0;
					length = length + seglen;
				end

			else
				length = getPathLength(gdata, parse.(Int64, elements[6:end]))
			end
			push!(gdata.graphEdgeLengths, e=>length)
		end
		# Weed out any duplicate vertices and load them into the data struct
		gdata.graphVertices = unique(sort(vertices))
		close(gfile)
		@info("$(length(vertices)) Candidate Graph vertices loaded.")
	else
		# If the CandidateNetwork file does not exist, throw the appropriate error messages
		@warn("File $(joinpath(SimCCSpro.dir, filename)) does not exist!")
		@warn("No Candidate Graph file found!")
		@warn("Generating and saving candidate network")
		generateCandidateNetwork!(gdata, secondOrderDelaunayEdges=secondOrderDelaunayEdges)
		saveCandidateNetwork(gdata)
	end
	gdata.input_candidategraph = DataInput()
	gdata.input_candidategraph.dir = SimCCSpro.dir
	gdata.input_candidategraph.file = filename
	gdata.input_candidategraph.hash = createhash(gdata.graphVertices)
	gdata.input_candidategraph.date = Dates.unix2datetime(mtime(joinpath(SimCCSpro.dir, filename)))
	return nothing
end



@inject_timer function LoadGeometriesFromCandidateNetworkShapefile(shapefile)

	shapefileGeoms = Dict{Edge, ArchGDAL.IGeometry}();
	ArchGDAL.read(shapefile) do ds
		# println("dataset $ds")
		ArchGDAL.getlayer(ds, 0) do lyr
			# println("layer $lyr")

			fc = ArchGDAL.nfeature(lyr, true);
			for _=1:fc
				ArchGDAL.nextfeature(lyr) do feature
					geom = ArchGDAL.getgeom(feature, 0);

					# expected to be in NAD83 already
					linkv1_idx = ArchGDAL.findfieldindex(feature, "LinkV1");
					linkv1 = ArchGDAL.getfield(feature, linkv1_idx);
					linkv2_idx = ArchGDAL.findfieldindex(feature, "LinkV2");
					linkv2 = ArchGDAL.getfield(feature, linkv2_idx);

					linkv1 = Int64(linkv1);
					linkv2 = Int64(linkv2);
					edge = Edge(linkv1, linkv2);

					shapefileGeoms[edge] = geom;

				end
			end
		end
	end
	return shapefileGeoms;
end



"""
$(DocumentFunction.documentfunction(loadDelaunayPairs!;
maintext="""
Load Delaunay Pairs
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"filename"=>"Input file name")))

Returns:

- nothing

Examples:

```julia
SimCCSpro.loadDelaunayPairs!(gdata, "DelaunayPaths.txt")
```
"""
@inject_timer function loadDelaunayPairs!(gdata::Data, scenario::AbstractString=gdata.scenario; intermodal::Bool=false, filename::AbstractString=joinpath("Scenarios", scenario, "Network", "DelaunayNetwork", "DelaunayPaths.txt"), secondOrderDelaunayEdges::Bool=false)
	if isfile(joinpath(SimCCSpro.dir, filename)) # Check for the existence of the DelaunayPaths file
		@info("Loading Delaunay Pairs from $(joinpath(SimCCSpro.dir, filename)) ...")
		gfile = open(joinpath(SimCCSpro.dir, filename))
		# Skip the first row
		readline(gfile)
		# Set up a vector to hold the Delaunay pairs
		pairs = Vector{Edge}()
		# Iterate through the remaining lines of the DelaunayPaths.txt file
		while !eof(gfile)
			line = readline(gfile)
			elements = split(line)
			# Get the cell numbers for the vertices of each edge
			v1 = parse(Int64, elements[5])
			v2 = parse(Int64, elements[6])
			push!(pairs, Edge(v1, v2))
		end
		close(gfile)
		@info("$(length(pairs)) Delaunay Pairs loaded.")
		# Load the Delaunay Pairs vector into the data struct
		gdata.delaunayPairs = pairs
	else
		# If the DelaunayPaths file does not exist, throw the appropriate error messages
		@warn("File $(joinpath(SimCCSpro.dir, filename)) does not exist!")
		@warn("No Delaunay Pairs file found!")
		@warn("Generating and saving Delunay pairs")
		method = :NativeDelaunay
		sourceSinkCellList = sourceSinkToCells(gdata; intermodal=intermodal) # Get the list of source and sink cells
		edges = generateDelaunayNetwork(gdata, sourceSinkCellList, method, secondOrderDelaunayEdges)
		gdata.delaunayPairs = edges
		saveDelaunayNetwork(gdata, edges, secondOrderDelaunayEdges=secondOrderDelaunayEdges)
	end
	gdata.input_delaunaypairs = DataInput()
	gdata.input_delaunaypairs.dir = SimCCSpro.dir
	gdata.input_delaunaypairs.file = filename
	gdata.input_delaunaypairs.hash = createhash(gdata.delaunayPairs)
	gdata.input_delaunaypairs.date = Dates.unix2datetime(mtime(joinpath(SimCCSpro.dir, filename)))
	return nothing
end

"""
$(DocumentFunction.documentfunction(loadPriceConfiguration!;
maintext="""
Load Price Configuration
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"filename"=>"Input file name")))

Returns:

- nothing

Examples:

```julia
SimCCSpro.loadPriceConfiguration!(gdata, "Price.txt")
```
"""
@inject_timer function loadPriceConfiguration!(gdata::Data, scenario::AbstractString=gdata.scenario; filename::AbstractString=joinpath(SimCCSpro.dir, "Scenarios", scenario, "Configurations", "timeInput.csv"))
	if isfile(filename)
		@info("Loading Price Configuration from $(filename) ...")
		gfile = open(filename)
		readline(gfile)
		pairs = Vector{Edge}()
		while !eof(gfile)
			line = readline(gfile)
			elements = split(line)
			v1 = parse(Int64, elements[5])
			v2 = parse(Int64, elements[6])
			push!(pairs, Edge(v1, v2))
		end
		close(gfile)
		@info("$(length(pairs)) Delaunay Pairs loaded.")
		gdata.delaunayPairs = pairs
	else
		@warn("File $(filename) does not exist!")
		@error("No Price Configuration file found!")
	end
	return nothing
end

"""
$(DocumentFunction.documentfunction(loadTimeConfiguration!;
maintext="""
Load Time Configuration
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"filename"=>"Input file name")))

Returns:

- nothing

Examples:

```julia
SimCCSpro.loadTimeConfiguration!(gdata, "timeInput.csv")
```
"""
@inject_timer function loadTimeConfiguration!(gdata::Data, scenario::AbstractString=gdata.scenario; filename::AbstractString)
	if isfile(filename)
		@info("Loading Time Configuration from $(filename) ...")
		gfile = open(filename)
		readline(gfile)
		timeEntries = Vector{}()
		while !eof(gfile)
			line = readline(gfile)
			elements = split(line, ",")

			timeslot = parse(Float64, elements[1])
			numYears = parse(Float64, elements[2])
			capTarget = parse(Float64, elements[3])

			push!(timeEntries, [timeslot, numYears, capTarget])
		end
		close(gfile)
		@info("$(length(timeEntries)) Time entries loaded")
		gdata.timeConfiguration = timeEntries
	else
		@warn("File $(filename) does not exist!")
		@error("No Time Configuration file found!")
	end
	return nothing
end

"""
$(DocumentFunction.documentfunction(load_costs_cells;
maintext="""
Load per-cell costs
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"gfile"=>"IOStream of cost file")))

Returns:

- costs: a matrix of the costs from each cell to the eight adjacent cells
- cellneighbors: a matrix of the adjacent cell numbers for each cell

Examples:

```julia
SimCCSpro.load_costs_cells(gdata, gfile)
```  
"""
@inject_timer function load_costs_cells(gdata::Data, gfile)
	# Create a matrix to hold the costs for each cell
	costs = Matrix{Float64}(undef, gdata.width * gdata.height + 1, 8)
	# Set initial cost for each cell to infinity
	costs .= Inf
	# Create a matrix to hold the adjacent cells
	cellneighbors = Matrix{Int64}(undef, gdata.width * gdata.height + 1, 8)
	# Set the initial neighbors for each cell to 0
	cellneighbors .= 0

	# The body of each cost file is composed of alternating lines
	# The first row contains the cell number of the cell in question, followed by cell numbers for up to eight adjacent cells
	# The second row contains the costs to reach each of those adjacent cells

	# Read the line containing the cell numbers for the first cell in the file
	linecell = readline(gfile)
	# Iterate through the remaining lines of the file
	while !eof(gfile)
		# Read the line containing the costs to reach each adjacent cell
		linecost = readline(gfile)
#		@show linecost
		# Split the line with cell numbers into an array
		cells = floor.(Int64, parse.(Float64, split(linecell)))
		# Split the line with the costs into an array
		cost = parse.(Float64, split(linecost))
		# Store the cell costs for each adjacent cell in the costs matrix
		costs[cells[1], 1:length(cost)] .= cost
		# Store the cell numbers for each adjacent cell in the cellneighbors array matrix
		cellneighbors[cells[1], 1:length(cost)] .= cells[2:end]
		# Read the line containing the cell numbers for the next cell in the file
		linecell = readline(gfile)
	end
	return costs, cellneighbors
end

"""
$(DocumentFunction.documentfunction(createhash;
maintext="""
Create a hash
""",
argtext=Dict("filename"=>"File name",
			"a"=>"Any object")))
Returns:

- Hash

Examples:

```julia
SimCCSpro.createhash("a.csv")
```
"""
function createhash(filename::String)::String
	hash = ""
	if isfile(filename)
		open(filename) do f
			hash = SHA.bytes2hex(SHA.sha2_256(f))
		end
	else
		@warn("File $(filename) does not exist!")
	end
	return hash
end

function createhash(a::Any)::UInt64
	return hash(a)
end

"""
$(DocumentFunction.documentfunction(load_terminal!;
maintext="""
Load the intermodal terminals
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data")))
Returns:

- Nothing

Examples:

```julia
SimCCSpro.load_terminal!(gdata)
```
"""
@inject_timer function load_terminal!(gdata::Data, scenario::AbstractString=gdata.scenario; filename::AbstractString=joinpath("Scenarios", scenario, "ports.csv"))
	if isfile(joinpath(SimCCSpro.dir, filename)) # Check for the existance of the terminals file
		gfile = CSV.Rows(joinpath(SimCCSpro.dir, filename), header=1) # Load the csv
		terminals = Vector{Terminal}(undef, 0) # Create a vector to hold the terminals
		for row in gfile # Iterate through the csv and store the data
			terminal = Terminal()
			terminal.code = row[1]
			terminal.portName = row[2]
			terminal.terminalName = row[3]
			terminal.state = row[4]
			terminal.lat = parse(Float64, row[5])
			terminal.lon = parse(Float64, row[6])
			terminal.cellNum = getCellNum(gdata, terminal.lat, terminal.lon) # Get the cell number and store it
			push!(terminals, terminal) # Add the current terminal to the terminals vector
		end
		gdata.terminals = terminals # Store the terminals in the data structure
		@info("$(length(terminals)) terminals loaded.")
	else
		@warn("File $(filename) does not exist!")
		@error("No terminals file found!")
	end
end

"""
$(DocumentFunction.documentfunction(load_shippingCost!;
maintext="""
Load the shipping cost between intermodal terminals
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data")))
Returns:

- Nothing

Examples:

```julia
SimCCSpro.load_shippingCost!(gdata)
```
"""
@inject_timer function load_shippingCost!(gdata::Data, scenario::AbstractString=gdata.scenario; filename::AbstractString=joinpath("Scenarios", scenario, "shipping_cost.csv"))
	if isfile(joinpath(SimCCSpro.dir, filename)) # Check for the existance of the shipping cost file
		gfile = CSV.Rows(joinpath(SimCCSpro.dir, filename), header=1) # Load the csv
		shippingCosts = Dict{ODPair, Float64}() # Create a dictionary to hold the shipping costs
		for row in gfile # Iterate through the csv and store the data
			originCode = row[1]
			for column in 2:length(row)
				destinationCode = gfile.names[column]
				od = ODPair(originCode, String(destinationCode))
				shippingCosts[od] = parse(Float64, row[column])
			end
		end
		for od in keys(shippingCosts) # Iterate through the OD pairs and fill the shipping costs in the other half of the table
			if od.origin != od.destination && shippingCosts[od] == 0 
				od2 = ODPair(od.destination, od.origin)
				shippingCosts[od] = shippingCosts[od2]
			end
		end
		gdata.shippingCosts = shippingCosts # Store the shipping costs in the data structure
		@info("Shipping costs for $(length(shippingCosts)) links loaded.")
	else
		@warn("File $(filename) does not exist!")
		@error("No shipping costs file found!")
	end
end

"""
$(DocumentFunction.documentfunction(load_costs_cells_JLD2;
maintext="""
Load per-cell costs from the JLD2 cost surface file
""",
argtext=Dict("network"=>"The network data structure from the JLD2 file",
			"numRows"=>"Number of rows in the network",
			"numCols"=>"Number of columns in the network")))

Returns:

- costs: a matrix of the costs from each cell to the eight adjacent cells
- cellneighbors: a matrix of the adjacent cell numbers for each cell

Examples:

```julia
SimCCSpro.load_costs_cells_JLD2(network, nRows, nCols)
```  
"""
@inject_timer function load_costs_cells_JLD2(network, numRows::Int64, numCols::Int64)
	
	# Create a matrix to hold the costs for each cell
	costs = Matrix{Float64}(undef, numCols * numRows + 1, 8)
	# Set initial cost for each cell to infinity
	costs  .= Inf
	# Create a matrix to hold the adjacent cells
	cellneighbors =  Matrix{Int64}(undef, numCols * numRows + 1, 8)
	# Set the initial neighbors for each cell to 0
	cellneighbors .= 0

	# for every cell in the surface
	for i in 1:size(network)[1]
		j = 1

		#get right neighbor
		if i%numCols !=0
			neighborCell = i + 1
			costs[i, j] = network[i, 1]
			cellneighbors[i, j] = neighborCell
			j += 1
		end

		#get bottom right neighbor
		if i%numCols !=0 && i < numCols * (numRows - 1)
			neighborCell = i + numCols + 1
			costs[i, j] = network[i, 2]
			cellneighbors[i, j] = neighborCell
			j += 1
		end

		#get bottom neighbor
		if i <= numCols * (numRows - 1)
			neighborCell = i + numCols
			costs[i, j] = network[i, 3]
			cellneighbors[i, j] = neighborCell
			j += 1
		end

		#get bottom left neighbor
		if i%numCols !=1 && i <= numCols * (numRows - 1)
			neighborCell = i + numCols - 1
			costs[i, j] = network[i, 4]
			cellneighbors[i, j] = neighborCell
			j += 1
		end

        #get left neighbor
        if i%numCols != 1
			neighborCell = i - 1
			costs[i, j] = network[neighborCell, 1]
			cellneighbors[i, j] = neighborCell
			j += 1
        end

        #get upper left neighbor
        if i%numCols != 1 && i > numCols
			neighborCell = i - numCols -1
			costs[i, j] = network[neighborCell, 2]
			cellneighbors[i, j] = neighborCell
			j += 1

        end
        #get top neighbor
        if i > numCols
			neighborCell = i - numCols
			costs[i, j] = network[neighborCell, 3]
			cellneighbors[i, j] = neighborCell
			j += 1
        end
        
		#get upper right neighbor
        if i > numCols && i%numCols != 0
			neighborCell = i - numCols + 1
			costs[i, j] = network[neighborCell, 4]
			cellneighbors[i, j] = neighborCell
			j += 1
        end
    end

	# Replace -9999.0 with Inf
	replace!(costs, -9999=>Inf)
	# Replace cell neighbors with 0 where costs == Inf
	cellneighbors[findall(x -> x==Inf, costs)] .= 0
	
	return costs, cellneighbors
end