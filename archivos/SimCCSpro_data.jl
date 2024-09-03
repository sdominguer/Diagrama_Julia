import Geodesy
import Dates
import GMT
import ArchGDAL
using DataStructures


### Structs ####

# Data structure for storing sinks

mutable struct Sink
	sco2tId::String # Sco2tId
	bg_id::Int32 # The 10, 20, 30, 40 of 50k basegrid id
	form::String # Formation
	land::String # Offshore/Onshore
	stg_cap::Float64 # Storage Capacity (MtCO2)
	stg_u_cost::Float64 # Storage Unit Cost ($t/tCO2)
	stg_credit::Float64 # Storage credit ($/tCO2)
	x_lon::Float64 # x coordinate/longitude
	y_lat::Float64 # y coordinate/latitude
	cap_rank::Int32
	cos_rank::Int32
	cellNum::Int64 # Cell number of the cell where the sink is located
	filterValue::String # Column values use for filtering the sinks
	filterText::String # Column texts use for filtering the sinks

	# Constructor
	Sink() = new("", 0, "", "", 0., 0., 0., 0., 0., 0, 0, 0, "", "")
end

# Data structure for storing sources

mutable struct Source
	co2ncordId::String # Co2ncordId
	facilityId::String # Facility Id
	fac_name::String # Facility name
	frs_id::String # Facility Registry Service ID
	state::String # State
	county::String # County
	city::String # city
	address::String # Street address
	x_lon::Float64 # x coordinate/longitude
	y_lat::Float64 # y coordinate/latitude
	cellNum::Int64 # Cell number of the cell where the source is located
	primary::String # Primary CO2 Sector
	secondary::String # Secondary CO2 Sector
	cap_stream::String # Capture Stream (Combustion, Rotary Kiln, Pulp Processing Emissions...)
	capturable::Float64 # Capturable CO2 (MtCO2/yr)
	cap_u_cost::Float64 # Estimated Capture Unit Cost ($/tCO2)
	filterValue::String # Column vvalues use for filtering the sources
	filterText::String # Column texts use for filtering the sources

	# Constructor
	Source() = new("", "", "", "", "", "", "", "", 0., 0., 0, "", "", "", 0., 0., "", "")
end

# Data structure for storing intermodal terminals
mutable struct Terminal
	code::String
	portName::String
	terminalName::String
	state::String
	lat::Float64
	lon::Float64
	cellNum::Int64
	# Constructor
	Terminal() = new("","","","",0.,0.,0)
end

# Data structure for storing linear components
mutable struct LinearComponent
	conSlope::Float64 # Slope and intercept of a linear function describing the construction cost; con = construction
	conIntercept::Float64
	rowSlope::Float64 # Slope and intercept of a linear function describing the right-of-way cost; row = right of way
	rowIntercept::Float64
	maxCapacity::Float64 # Maximum pipeline capacity
	# Constructor
	LinearComponent() = new(0., 0., 0., 0., 0.)
end

# Data structure for storing edges
struct Edge
	v1::Int64
	v2::Int64
	function Edge(v1::Int64, v2::Int64)
		if (v1 > v2)
			new(v2, v1)
		else
			new(v1, v2)
		end
	end
end

# Data structure for storing unidirectional edges
struct UnidirEdge # TODO we should consider removing this structure
	v1::Int64
	v2::Int64
end

struct ODPair
	origin::String
	destination::String
end

mutable struct DataInput
	dir::String
	file::String
	hash::UInt64
	date::Dates.DateTime
	# Constructor
	DataInput() = new("", "", 0x000000000000, Dates.now())
end

# Data structure for storing SimCCS data
mutable struct Data
	project::String
	scenario::String
	case::String
	# Data Inputs
	input_constructioncosts::DataInput
	input_rightofwaycosts::DataInput
	input_routingcosts::DataInput
	input_sinks::DataInput
	input_sources::DataInput
	input_transport::DataInput
	input_candidategraph::DataInput
	input_delaunaypairs::DataInput

	allNodes::Int64 # number of nodes
	activeNodes::Int64 # number of active nodes
	projection::String # Proj4 string that contains projection information
	width::Int64 # nCols
	height::Int64 # nRows
	xllCorner::Float64 # x coordinate of the lower left corner of the map
	yllCorner::Float64 # y coordinate of the lower left corner of the map
	# projectionVersion=1 represents an unprojected decimal degree coordinate system
	# projectionVersion=2 represents a projected coordinate system
	projectionVersion::Int64
	cellSize::Float64 # Size of the cell in the same units as the x and y coordinates
	# Raw network information
	cellneighbors::Matrix{Int64} # Matrix of cells containing the ID of each adjacent cell
	rightOfWayCosts::Matrix{Float64} # Matrix of cells containing the right of way cost to build a pipeline to each adjacent cell
	constructionCosts::Matrix{Float64} # Matrix of cells containing the construction cost to build a pipeline to each adjacent cell
	routingCosts::Matrix{Float64} # Matrix of cells containing the routing cost to build a pipeline to each adjacent cell
	# Matrix of cells containing the routing cost to build a pipeline to each adjacent cell, modified by multiplying by .9999999 to make redundant paths less likely
	modifiedRoutingCosts::Matrix{Float64}

	# Source and sink data
	sources::Vector{Source}
	sources_select::Vector{Bool}
	
	sinks::Vector{Sink}
	sinks_select::Vector{Bool}

	terminals::Vector{Terminal}
	shippingCosts::OrderedDict{ODPair, Float64}
	linearComponents::Vector{LinearComponent}
	sourceSinkCellLocations::Vector{Int64} # Cell number for each source and sink node
	sourcesSinksWithinCostSurface::Bool # Are all sources, sinks and terminals within cost surface?

	# Candidate network graph information
	candidateNetworkName::AbstractString
	graphVertices::Vector{Int64} # Set of all vertices in graph (sources/sinks/junctions)
	graphEdgeCosts::OrderedDict{Edge, Float64} # Cost for each edge between vertices
	graphEdgeRoutes::Dict{Edge, Vector{Int64}} # Cell-to-cell route for each edge between vertices
	graphEdgeRightOfWayCosts::OrderedDict{Edge, Float64} # Cost for each edge between vertices
	graphEdgeConstructionCosts::OrderedDict{Edge, Float64} # Cost for each edge between vertices
	delaunayPairs::Vector{Edge} # Delaunay pairs
	graphEdgeLengths::Dict{Edge, Float64} # Length (km) of edge when following routing
	graphNeighbors::Dict{Int64, Set{Int64}} # Neighboring node of each node in the network
	sourceSinkRoutes::Dict{Edge, Vector{Edge}}

	# Configuration data
	timeConfiguration::Vector{Vector{Float64}}
	priceConfiguration::Vector{Float64}
	capTargetConfiguration::Vector{Float64}

	modelParams::String
	crf::Float64 # Cost Reduction Factor (based on length of scenario and assumptions about future value of money)
	interestRate::Float64
	numYears::Int64
	carbonTax::Float64
	carbonTaxCreditSaline::Float64
	carbonTaxCreditOnG::Float64

	# Constructor
	Data() = new()
end

# Data structor for storing source output
mutable struct SourceOutput
	co2ncordId::String
	facilityId::String
	frs_id::String
	fac_name::String
	x::Float64
	y::Float64
	state::String
	county::String
	city::String
	address::String
	primary::String
	secondary::String
	cap_stream::String
	pctCaptured::Float64
	pctReleased::Float64
	capturableCO2::Float64
	capturedCO2::Float64
	captureCost::Float64
	captureUnitCost::Float64
	cellNum::Int64
	filterValue::String
	filterText::String

	# Constructor
	SourceOutput() = new("", "", "", "", 0.0, 0.0, "", "", "", "", "", "", "", 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, "", "")
end

# Data structure for storing solutions
mutable struct SimccsSolution
	sourceCapture::Dict{String, Float64} # Dictionary with source FacilityIds as keys and amount captured per year as values
	sourceCost::Dict{String, Float64} # Dictionary with source FacilityIds as keys and total capture cost per year as values
	sinkStorage::Dict{String, Float64} # Dictionary with sink Scot2tIds as keys and amount stored per year as values
	sinkCost::Dict{String, Float64} # Dictionary with sink Scot2tIds as keys and total storage cost per year as values
	sinkStorageCredit::Dict{String, Float64} # Dictionary with sink Soct2tIds as keys and storage/CO2 credit ($/tCO2) as values

	pipelineFlow::Dict{UnidirEdge, Float64} # Dictionary with edges as keys and flow per year as values
	pipelineCost::Dict{UnidirEdge, Float64} # Dictionary with edges as keys and cost per year as values
	pipelineTrend::Dict{UnidirEdge, Int64}  # Dictionary with edges as keys and trend as values
	linkFlow::Dict{ODPair, Float64} # Dictionary with intermodal terminal origins and destinations as keys and flow per year as values
	linkCost::Dict{ODPair, Float64} # Dictionary with intermodal terminal origins and destinations as keys and cost per year as values
	annualCapture::Float64 # Annual amount captured
	numYears::Int64 # Number of years the solution was run for
	crf::Float64 # Cost reduction factor
	interestRate::Float64 # Interest rate used to calculate the CRF
	totalCost::Float64 # Total cost
	combinedCaptureCosts::Float64 # Capture costs for all sources
	combinedStorageCosts::Float64 # Storage costs for all sinks
	combinedPipelineCosts::Float64 # Transport costs for all pipelines
	combinedLinkCosts:: Float64 # Transport costs for all intermodal links
	transportCosts::Float64 # Transport costs for all pipelines and intermodal links
	collectedCredit::Float64 # The carbon storage credits collected
	input_costweights::DataInput # DataInput for the costweights file
	input_rightofwaycosts::DataInput # DataInput for the right of way costs file
	input_routingweights::DataInput # DataInput for the routing weights file
	input_sinks::DataInput # DataInput for the sinks file
	input_sources::DataInput # DataInput for the sources file
	input_transport::DataInput # DataInput for the linear component file
	input_candidategraph::DataInput # DataInput for the candidate graph file
	input_delaunaypairs::DataInput # DataInput for the Delaunay pairs file
	SimccsSolution() = new()
end

# Data structure for storing solution summary
mutable struct SimccsSolutionSummary
	seconds::Int64 # Number of model run seconds since the run started (excluding parse solution time)
	gap::Float64 # Current gap after the intermediate run
	deltaGap::Float64 # Delta between the current and previous gap
	numberOfCapturedSources::Int64 # Number of captured sources
	numberOfUtilizedSinks::Int64 # Number of utilized sinks
	lengthOfPipline::Float64 # Total length of pipeline (km)
	annualCapture::Float64 # Annual amount captured
	
	combinedCaptureCosts::Float64 # Capture costs for all sources
	transportCosts::Float64 # Transport costs for all pipelines and intermodal links
	combinedPipelineCosts::Float64 # Transport costs for all pipelines
	combinedLinkCosts:: Float64 # Transport costs for all intermodal links
	combinedStorageCosts::Float64 # Storage costs for all sinks
	collectedCredit::Float64 # The carbon storage credits collected
	totalCost::Float64 # Total cost

	SimccsSolutionSummary() = new()
end


# need to implement copy for all the structs to get copy for the "Data" struct

# just going to make every "copy" a deepcopy


Base.copy(sink::Sink) = begin
	sn = Sink();
    sn.sco2tId = sink.sco2tId;
	sn.bg_id = sink.bg_id;
	sn.form = sink.form;
	sn.land = sink.land;
	sn.stg_cap = sink.stg_cap;
	sn.stg_credit = sink.stg_credit;
	sn.x_lon = sink.x_lon;
	sn.y_lat = sink.y_lat;
	sn.cap_rank = sink.cap_rank;
	sn.cos_rank = sink.cos_rank;
	sn.cellNum = sink.cellNum;
	sn.filterValue = sink.filterValue;
	sn.filterText = sink.filterText;
	return sn;
end

Base.copy(source::Source) = begin 
    src = Source();
	src.co2ncordId = source.co2ncordId;
	src.facilityId = source.facilityId;
	src.fac_name = source.fac_name;
	src.frs_id = source.frs_id;
	src.state = source.state;
	src.county = source.county;
	src.city = source.city;
	src.address = source.address;
	src.x_lon = source.x_lon;
	src.y_lat = source.y_lat;
	src.cellNum = source.cellNum;
	src.primary = source.primary;
	src.secondary = source.secondary;
	src.cap_stream = source.cap_stream;
	src.capturable = source.capturable;
	src.cap_u_cost = source.cap_u_cost;
	src.filterValue = source.filterValue;
	src.filterText = source.filterText;
	return src;
end


Base.copy(terminal::Terminal) = begin
	t = Terminal();
	t.code = terminal.code;
	t.portName = terminal.portName;
	t.terminalName = terminal.terminalName;
	t.state = terminal.state;
	t.lat = terminal.lat;
	t.lon = terminal.lon;
	t.cellNum = terminal.cellNum;	
	return t;
end


Base.copy(linearComponent::LinearComponent) = begin
	lc = LinearComponent();
	lc.conSlope = linearComponent.conSlope;
	lc.conIntercept = linearComponent.conIntercept;
	lc.rowSlope = linearComponent.rowSlope;
	lc.rowIntercept = linearComponent.rowIntercept;
	lc.maxCapacity = linearComponent.maxCapacity;	
	return lc;
end

Base.copy(edge::Edge) = Edge(edge.v1, edge.v2);

Base.copy(odPair::ODPair) = ODPair(odPair.origin, odPair.destination);


Base.copy(dataInput::DataInput) = begin
	di = DataInput();
	di.dir = dataInput.dir;
	di.file = dataInput.file;
	di.hash = dataInput.hash;
	di.date = dataInput.date;
	return di;
end


Base.copy(gdata::Data) = begin
	gd = Data();
	if isdefined(gdata, :project) gd.project = gdata.project; end
	if isdefined(gdata, :scenario) gd.scenario = gdata.scenario; end
	if isdefined(gdata, :case) gd.case = gdata.case; end
	if isdefined(gdata, :input_constructioncosts) gd.input_constructioncosts = copy(gdata.input_constructioncosts); end
	if isdefined(gdata, :input_rightofwaycosts) gd.input_rightofwaycosts = copy(gdata.input_rightofwaycosts); end
	if isdefined(gdata, :input_routingcosts) gd.input_routingcosts = copy(gdata.input_routingcosts); end
	if isdefined(gdata, :input_sinks) gd.input_sinks = copy(gdata.input_sinks); end
	if isdefined(gdata, :input_sources) gd.input_sources = copy(gdata.input_sources); end
	if isdefined(gdata, :input_transport) gd.input_transport = copy(gdata.input_transport); end
	if isdefined(gdata, :input_candidategraph) gd.input_candidategraph = copy(gdata.input_candidategraph); end
	if isdefined(gdata, :input_delaunaypairs) gd.input_delaunaypairs = copy(gdata.input_delaunaypairs); end
	if isdefined(gdata, :allNodes) gd.allNodes = gdata.allNodes; end
	if isdefined(gdata, :activeNodes) gd.activeNodes = gdata.activeNodes; end
	if isdefined(gdata, :projection) gd.projection = gdata.projection; end
	if isdefined(gdata, :width) gd.width = gdata.width; end
	if isdefined(gdata, :height) gd.height = gdata.height; end
	if isdefined(gdata, :xllCorner) gd.xllCorner = gdata.xllCorner; end
	if isdefined(gdata, :yllCorner) gd.yllCorner = gdata.yllCorner; end
	if isdefined(gdata, :projectionVersion) gd.projectionVersion = gdata.projectionVersion; end
	if isdefined(gdata, :cellSize) gd.cellSize = gdata.cellSize; end
	if isdefined(gdata, :cellneighbors) gd.cellneighbors = deepcopy(gdata.cellneighbors); end
	if isdefined(gdata, :rightOfWayCosts) gd.rightOfWayCosts = deepcopy(gdata.rightOfWayCosts); end
	if isdefined(gdata, :constructionCosts) gd.constructionCosts = deepcopy(gdata.constructionCosts); end
	if isdefined(gdata, :routingCosts) gd.routingCosts = deepcopy(gdata.routingCosts); end
	if isdefined(gdata, :modifiedRoutingCosts) gd.modifiedRoutingCosts = deepcopy(gdata.modifiedRoutingCosts); end
	if isdefined(gdata, :sources) gd.sources = deepcopy(gdata.sources); end
	if isdefined(gdata, :sources_select) gd.sources_select = deepcopy(gdata.sources_select); end
	if isdefined(gdata, :sinks) gd.sinks = deepcopy(gdata.sinks); end
	if isdefined(gdata, :sinks_select) gd.sinks_select = deepcopy(gdata.sinks_select); end
	if isdefined(gdata, :terminals) gd.terminals = deepcopy(gdata.terminals); end
	if isdefined(gdata, :shippingCosts) gd.shippingCosts = deepcopy(gdata.shippingCosts); end
	if isdefined(gdata, :linearComponents) gd.linearComponents = deepcopy(gdata.linearComponents); end
	if isdefined(gdata, :sourceSinkCellLocations) gd.sourceSinkCellLocations = deepcopy(gdata.sourceSinkCellLocations); end
	if isdefined(gdata, :sourcesSinksWithinCostSurface) gd.sourcesSinksWithinCostSurface = gdata.sourcesSinksWithinCostSurface; end
	if isdefined(gdata, :candidateNetworkName) gd.candidateNetworkName = gdata.candidateNetworkName; end
	if isdefined(gdata, :graphVertices) gd.graphVertices = deepcopy(gdata.graphVertices); end
	if isdefined(gdata, :graphEdgeCosts) gd.graphEdgeCosts = deepcopy(gdata.graphEdgeCosts); end
	if isdefined(gdata, :graphEdgeRoutes) gd.graphEdgeRoutes = deepcopy(gdata.graphEdgeRoutes); end
	if isdefined(gdata, :graphEdgeRightOfWayCosts) gd.graphEdgeRightOfWayCosts = deepcopy(gdata.graphEdgeRightOfWayCosts); end
	if isdefined(gdata, :graphEdgeConstructionCosts) gd.graphEdgeConstructionCosts = deepcopy(gdata.graphEdgeConstructionCosts); end
	if isdefined(gdata, :delaunayPairs) gd.delaunayPairs = deepcopy(gdata.delaunayPairs); end
	if isdefined(gdata, :graphEdgeLengths) gd.graphEdgeLengths = deepcopy(gdata.graphEdgeLengths); end
	if isdefined(gdata, :graphNeighbors) gd.graphNeighbors = deepcopy(gdata.graphNeighbors); end
	if isdefined(gdata, :sourceSinkRoutes) gd.sourceSinkRoutes = deepcopy(gdata.sourceSinkRoutes); end
	if isdefined(gdata, :timeConfiguration) gd.timeConfiguration = deepcopy(gdata.timeConfiguration); end
	if isdefined(gdata, :priceConfiguration) gd.priceConfiguration = deepcopy(gdata.priceConfiguration); end
	if isdefined(gdata, :capTargetConfiguration) gd.capTargetConfiguration = deepcopy(gdata.capTargetConfiguration); end
	if isdefined(gdata, :modelParams) gd.modelParams = gdata.modelParams; end
	if isdefined(gdata, :crf) gd.crf = gdata.crf; end
	if isdefined(gdata, :interestRate) gd.interestRate = gdata.interestRate; end
	if isdefined(gdata, :numYears) gd.numYears = gdata.numYears; end
	if isdefined(gdata, :carbonTax) gd.carbonTax = gdata.carbonTax; end
	if isdefined(gdata, :carbonTaxCreditSaline) gd.carbonTaxCreditSaline = gdata.carbonTaxCreditSaline; end
	if isdefined(gdata, :carbonTaxCreditOnG) gd.carbonTaxCreditOnG = gdata.carbonTaxCreditOnG; end
	return gd;
end


Base.copy(sourceOutput::SourceOutput) = begin
	so = SourceOutput();
	so.co2ncordId = sourceOutput.co2ncordId;
	so.facilityId = sourceOutput.facilityId;
	so.frs_id = sourceOutput.frs_id;
	so.fac_name = sourceOutput.fac_name;
	so.x = sourceOutput.x;
	so.y = sourceOutput.y;
	so.state = sourceOutput.state;
	so.county = sourceOutput.county;
	so.city = sourceOutput.city;
	so.address = sourceOutput.address;
	so.primary = sourceOutput.primary;
	so.secondary = sourceOutput.secondary;
	so.cap_stream = sourceOutput.cap_stream;
	so.pctCaptured = sourceOutput.pctCaptured;
	so.pctReleased = sourceOutput.pctReleased;
	so.capturableCO2 = sourceOutput.capturableCO2;
	so.capturedCO2 = sourceOutput.capturedCO2;
	so.captureCost = sourceOutput.captureCost;
	so.captureUnitCost = sourceOutput.captureUnitCost;
	so.cellNum = sourceOutput.cellNum;
	so.filterValue = sourceOutput.filterValue;
	so.filterText = sourceOutput.filterText;
	return so;
end


Base.copy(simccsSolution::SimccsSolution) = begin
	sol = SimccsSolution();
	if isdefined(simccsSolution, :sourceCapture) sol.sourceCapture = deepcopy(simccsSolution.sourceCapture); end
	if isdefined(simccsSolution, :sourceCost) sol.sourceCost = deepcopy(simccsSolution.sourceCost); end
	if isdefined(simccsSolution, :sinkStorage) sol.sinkStorage = deepcopy(simccsSolution.sinkStorage); end
	if isdefined(simccsSolution, :sinkCost) sol.sinkCost = deepcopy(simccsSolution.sinkCost); end
	if isdefined(simccsSolution, :sinkStorageCredit) sol.sinkStorageCredit = deepcopy(simccsSolution.sinkStorageCredit); end
	if isdefined(simccsSolution, :pipelineFlow) sol.pipelineFlow = deepcopy(simccsSolution.pipelineFlow); end
	if isdefined(simccsSolution, :pipelineCost) sol.pipelineCost = deepcopy(simccsSolution.pipelineCost); end
	if isdefined(simccsSolution, :pipelineTrend) sol.pipelineTrend = deepcopy(simccsSolution.pipelineTrend); end
	if isdefined(simccsSolution, :linkFlow) sol.linkFlow = deepcopy(simccsSolution.linkFlow); end
	if isdefined(simccsSolution, :linkCost) sol.linkCost = deepcopy(simccsSolution.linkCost); end
	if isdefined(simccsSolution, :annualCapture) sol.annualCapture = simccsSolution.annualCapture; end
	if isdefined(simccsSolution, :numYears) sol.numYears = simccsSolution.numYears; end
	if isdefined(simccsSolution, :crf) sol.crf = simccsSolution.crf; end
	if isdefined(simccsSolution, :interestRate) sol.interestRate = simccsSolution.interestRate; end
	if isdefined(simccsSolution, :totalCost) sol.totalCost = simccsSolution.totalCost; end
	if isdefined(simccsSolution, :combinedCaptureCosts) sol.combinedCaptureCosts = simccsSolution.combinedCaptureCosts; end
	if isdefined(simccsSolution, :combinedStorageCosts) sol.combinedStorageCosts = simccsSolution.combinedStorageCosts; end
	if isdefined(simccsSolution, :combinedPipelineCosts) sol.combinedPipelineCosts = simccsSolution.combinedPipelineCosts; end
	if isdefined(simccsSolution, :combinedLinkCosts) sol.combinedLinkCosts = simccsSolution.combinedLinkCosts; end
	if isdefined(simccsSolution, :transportCosts) sol.transportCosts = simccsSolution.transportCosts; end
	if isdefined(simccsSolution, :collectedCredit) sol.collectedCredit = simccsSolution.collectedCredit; end
	if isdefined(simccsSolution, :input_costweights) sol.input_costweights = copy(simccsSolution.input_costweights); end
	if isdefined(simccsSolution, :input_rightofwaycosts) sol.input_rightofwaycosts = copy(simccsSolution.input_rightofwaycosts); end
	if isdefined(simccsSolution, :input_routingweights) sol.input_routingweights = copy(simccsSolution.input_routingweights); end
	if isdefined(simccsSolution, :input_sinks) sol.input_sinks = copy(simccsSolution.input_sinks); end
	if isdefined(simccsSolution, :input_sources) sol.input_sources = copy(simccsSolution.input_sources); end
	if isdefined(simccsSolution, :input_transport) sol.input_transport = copy(simccsSolution.input_transport); end
	if isdefined(simccsSolution, :input_candidategraph) sol.input_candidategraph = copy(simccsSolution.input_candidategraph); end
	if isdefined(simccsSolution, :input_delaunaypairs) sol.input_delaunaypairs = copy(simccsSolution.input_delaunaypairs); end
    return sol;
end


#### Functions #### 
function getCellNum(gdata::Data, lat::Number, lon::Number)
	if gdata.projectionVersion == 1
		# In an unprojected coordinate system, call location to cell and return the cell number
		return locationToCell(gdata, lat, lon)
	elseif gdata.projectionVersion == 2
		x, y = projectLatLon([lat], [lon], gdata.projection) # Convert the latitude and longitude to x and y coordinates, call location to cell, and return the cell number
		return locationToCell(gdata, y, x) # lat is y, lon is x
	else
		@error("No valid projectionVersion $(gdata.projectionVersion) specified (1 or 2 expected)!")
	end
end


function locationToCell(gdata::Data, lat::Number, lon::Number)
	# Calculate how many rows from the top of the map the latitide cooresponds to
	row = gdata.height - (convert(Int64, floor((lat - gdata.yllCorner) / gdata.cellSize)) + 1) + 1
	# Calculate how many columns from the left side of the map the longitude corresponds to
	col = convert(Int64, floor((lon - gdata.xllCorner) / gdata.cellSize)) + 1
	# Convert the column and row position to a cellnumber and return
	return colRowToVectorized(gdata, col, row)
end


function colRowToVectorized(gdata::Data, col::Int64, row::Int64)
	# Convert column and row position to a cell number, with cell numbering starting in the upper left corner of the map and wrapping around at the end of each row
	return (row - 1) * gdata.width + col
end


# Convert from cell number to lat, lon
function cellToLocation(gdata::Data, cell::Int64)
	x, y = cellLocationToRawXY(gdata, cell) # get column (x) and row (y) based ont the cell number
	x -= .5 # subtract 0.5 so that you are in between
	y -= .5
	lat = (gdata.height - y) * gdata.cellSize + gdata.yllCorner # Calculate Y-lat
	lon = x * gdata.cellSize + gdata.xllCorner # Calculate X-lon
	return lon, lat
end


# Convert cell number to column number (x) and row number(y). (column and row numbering start at 1)
function cellLocationToRawXY(gdata::Data, cell::Int64)
	# NOTE: Cell counting starts at 1, not 0.
	y = convert(Int64, floor((cell - 1) / gdata.width + 1))
	x = convert(Int64, floor(cell - (y - 1) * gdata.width))
	return x, y
end


function struct_to_dict(gdata::Data, gdata_fields::Vector{Symbol})
	d = Dict()
	for f in gdata_fields
		push!(d, string(f) => getfield(gdata, f))
	end
	return d
end


function dict_to_struct!(gdata::Data, gdata_dict::AbstractDict)
	for f in keys(gdata_dict)
		setfield!(gdata, Symbol(f), gdata_dict[f])
	end
end


function indexCellsToSourceSink(gdata::Data)
	cellIndex = Dict{Int64, Tuple}()

	for source in gdata.sources[gdata.sources_select]# Iterate through each source
		id = 0	# using facilityId string with space cause problems when reading back the data from file
		cellIndex[source.cellNum] = ("SOURCE", id)
	end
	for sink in gdata.sinks[gdata.sinks_select]
		id = 0	# using scot2tId string with space cause problems when reading back he data from file	
		cellIndex[sink.cellNum] = ("SINK", id)
	end
	if isdefined(gdata, :terminals) # Check to see if gdata has a terminals attribute defined
		for terminal in gdata.terminals
			cellIndex[terminal.cellNum] = ("Terminal", 0)
		end
	end

	return cellIndex
end



"""
$(DocumentFunction.documentfunction(cellToSourceSink;
maintext="""
Determine whether a given cell is a Source, Sink, or intermodal Terminal and what the ID is.
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"cellNum"=>"Cell number")))

If a cell contains multiple sources, sinks, and/or terminals, will only return the first one it finds.

Returns:

- Type (SOURCE, SINK or TERMINAL) and ID (defaults to 0 for terminals)

Examples:

```julia
SimCCSpro.cellToSS(gdata, cellNum)
```
"""
function cellToSourceSink(gdata::Data, cellNum::Int64)
	type = ""
	id = 0

	for source in gdata.sources[gdata.sources_select]# Iterate through each source
		if cellNum == source.cellNum # Check the cell number against the sources cell number
			type = "SOURCE" # Set type to source
			#id = source.facilityId # Set id to the source's ID
			id = 0 # using facilityId string with space cause problems when reading back the data from file
		else
			for sink in gdata.sinks[gdata.sinks_select] # Iterate through each sink
				if cellNum == sink.cellNum # Check the cell number against the sources cell number
					type = "SINK" # Set type to sink
					#id = sink.sco2tId # Set id to the sink's ID
					id = 0	# using scot2tId string with space cause problems when reading back he data from file		
				else
					if isdefined(gdata, :terminals) # Check to see if gdata has a terminals attribute defined
						for terminal in gdata.terminals # Iterate through each terminal
							if cellNum == terminal.cellNum # Check the cell number against the terminal's cell number
								type = "Terminal" # Set type to terminal
								id = 0 # Set id to zero (no ID numbers for terminals)
							end
						end
					end
				end
			end
		end
	end

	return type, id
end

"""
$(DocumentFunction.documentfunction(sourceSinkToCells;
maintext="""
Get a vector of cell IDs for all sources and sinks.
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data")))

Returns:

- Vector of cell numbers for all sources and sinks

Examples:

```julia
SimCCSpro.sourceSinkToCells(gdata)
```
"""
function sourceSinkToCells(gdata::Data; intermodal::Bool=false)
	vertexCells = Vector{Int64}(undef, 0) # Create a vector to store the cell numbers

	for source in gdata.sources[gdata.sources_select] # Iterate through each source
		push!(vertexCells, source.cellNum) # Add the cell to the output vector
	end
	for sink in gdata.sinks[gdata.sinks_select] # Iterate through each sink
		push!(vertexCells, sink.cellNum) # Add the cell to the output vector
	end

	if intermodal
		for terminal in gdata.terminals # Iterate through each terminal
			push!(vertexCells, terminal.cellNum) # Add the cell to the output vector
		end
	end
	return vertexCells
end



"""
$(DocumentFunction.documentfunction(getCellCosts;
maintext="""
Get the construction and right-of-way costs (if present) for two adjacent cells.
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"v1"=>"cell ID of the origin cell",
			"v2"=>"cell ID of the destination cell")))

Returns:

- Costs for the two adjacent cells

Examples:

```julia
SimCCSpro.getCellCosts(gdata, v1, v2)
```
"""
function getCellCosts(gdata::Data, v1::Int64, v2::Int64)
	if size(gdata.rightOfWayCosts) == (0, 0) # Check to see if there are separate right-of-way costs
		# If there are no rightOfWayCosts, add the construction costs from the current cell to the next cell to the cost
		# findfirst gives us the index of the neighbor in gdata.cellneighbors.
		r1 = v1;
		c1 = findfirst(x -> x == v2, gdata.cellneighbors[v1,1:end]);
		# println("r1,c1 path: getting gdata.constructionCosts[$(r1), $(c1)]")
		return gdata.constructionCosts[r1,c1];
	else
		# If there are rightOfWayCosts, add the construction costs and right-of-way costs from the current cell to the next cell to the cost
		# findfirst gives us the index of the neighbor in gdata.cellneighbors.
		r2 = v1;
		c2 = findfirst(x -> x == v2, gdata.cellneighbors[v1,1:end])
		# println("r2,c2 path: getting gdata.constructionCosts[$(r2), $(c2)]")
		return gdata.constructionCosts[r2,c2] + gdata.rightOfWayCosts[r2,c2];
	end
end

# GMT
# PROJCS["Albers_Conical_Equal_Area",GEOGCS["GCS_WGS_1984",
# DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],
# PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],PROJECTION[
# "Albers"],
# PARAMETER["false_easting",0.0],PARAMETER["false_northing",0.0],
# PARAMETER["central_meridian",-96.0],PARAMETER["standard_parallel_1",29.5],
# PARAMETER["standard_parallel_2",45.5],PARAMETER["latitude_of_origin",23.0],
# UNIT["Meter",1.0]]


"""
Convert LAT/LON to Cartesian coordinates (x,y) in projection specified by proj4 string

$(DocumentFunction.documentfunction(projectLatLon))
"""
@inject_timer function projectLatLon(lat::Vector{Float64}, lon::Vector{Float64}, projection::String)
	proj_string = "-J"*projection*" -C"
	coordinates = GMT.mapproject(proj_string, [lon lat])
	return coordinates
end

"""
Convert Cartesian coordinates (x,y) in given projection to LAT/LON

$(DocumentFunction.documentfunction(projectedCoordsToLatLon))
"""
@inject_timer function projectedCoordsToLatLon(x::Vector{Float64}, y::Vector{Float64}, projection::String)
	proj_string = "-J"*projection*" -C -I"
	coordinates = GMT.mapproject(proj_string, [x y])
	return reverse(coordinates, dims=2)
end

"""
$(DocumentFunction.documentfunction(graph_neighbors!;
maintext="""
Find neighboring nodes for each node in the candidate graph
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data")))

Returns:

- Dictionary of neighbors, with cell IDs as keys and sets of cell IDs of neighboring cells as values

Examples:

```julia
SimCCSpro.graph_neighbors!(gdata, origin, destination)
```
"""
function graph_neighbors!(gdata)
	neighbors = Dict{Int64, Set}()
	for edge in keys(gdata.graphEdgeCosts)
		# Check if  v1 is already in the dictionary of neighbors and create if not
		if edge.v1 ∉ keys(neighbors)
			neighbors[edge.v1] = Set{Int64}()
		end
		push!(neighbors[edge.v1], edge.v2) # Make v2 a neighbor of v1
		# Check if v2 is already in the dictionary of neighbors and create if not
		if edge.v2 ∉ keys(neighbors)
			neighbors[edge.v2] = Set{Int64}()
		end
		push!(neighbors[edge.v2], edge.v1) # Make the v1 a neighbor of v2
	end
	gdata.graphNeighbors = neighbors
	return neighbors
end

"""
$(DocumentFunction.documentfunction(edgeToUnidirEdges;
maintext="""
Generates two unidirectional edges with the same vertices as the original edge
""",
argtext=Dict("edge"=>"SimCCS edge")))

Returns:

- Two unidirectional edges with the same vertices as the original edge

Examples:

```julia
SimCCSpro.edgeToUnidirEdges(edge)
```
"""
function edgeToUnidirEdges(edge::Edge)
	fromEdge = UnidirEdge(edge.v1, edge.v2)
	toEdge = UnidirEdge(edge.v2, edge.v1)
	return fromEdge, toEdge
end



"""
$(DocumentFunction.documentfunction(unidirEdgeToEdge;
maintext="""
Generates a non-unidirectional edge with the same vertices as the original unidirectional edge with the vetices in the same order as the edge in graphEdgeRoutes
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"unidirEdge"=>"SimCCS unidirecitonal edge")))

Returns:

- Edge with the same vertices as the original unidirecitonal edge

Examples:

```julia
SimCCSpro.unidirEdgeToEdge(gdata, unidirEdge)
```
"""
function unidirEdgeToEdge(gdata::Data, unidirEdge::UnidirEdge)
	if Edge(unidirEdge.v1, unidirEdge.v2) in keys(gdata.graphEdgeRoutes) # Check to see if the edge is in graphEdgeRoutes
		edge = Edge(unidirEdge.v1, unidirEdge.v2) # Create the edge
	elseif  Edge(unidirEdge.v2, unidirEdge.v2) in keys(gdata.graphEdgeRoutes) # Check to see if the reverse of the edge is in graphEdgeRoutes
		edge = Edge(unidirEdge.v2, unidirEdge.v1) # Create the edge``
	else
		@error("The edge $unidirEdge does not exist in graphEdgeRoutes")
	end
	return edge
end




"""
$(DocumentFunction.documentfunction(calculateLatLonDistance;
maintext="""
Calculates the great circle distance between two points defined by latitude and longitude (assuming a perfectly spherical earth).
""",
argtext=Dict("lat1"=>"Latitude of the first point",
			"lon1"=>"Longitude of the first point",
			"lat2"=>"Latitude of the second point",
			"lon2"=>"Longitude of the second point")))

Returns:

- Distance between the two points in kilometers

Examples:

```julia
SimCCSpro.calculateLatLonDistance(lat1, lon1, lat2, lon2)
```
"""
function calculateLatLonDistance(lat1::Float64, lon1::Float64, lat2::Float64, lon2::Float64)
	# Magic number is the raidus of earth in km
	distance = 2 * 6372.8 * asin(sqrt(sind((lat2 - lat1) / 2) ^ 2 + cosd(lat1) * cosd(lat2) * sind((lon2 - lon1) / 2) ^ 2))
	return distance
end



"""
$(DocumentFunction.documentfunction(getDistance;
maintext="""
Calculates the distance between two cells.
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"cell1"=>"Cell ID of the first cell",
			"cell2"=>"Cell ID of the second cell")))

Returns:

- Distance between cells in kilometers

Examples:

```julia
SimCCSpro.getDistance(gdata, cell1, cell2)
```
"""
function getDistance(gdata::Data, cell1::Int64, cell2::Int64)
	# Check the projection version
	if gdata.projectionVersion == 2 # If the projection uses projected coordinates and the cells area adjacient we can calculate the distance based on cell size
		cellSizeKM = gdata.cellSize / 1000
		offset = abs(cell1 - cell2)
		if offset == 1 || offset == gdata.width # If the absolute value of the distance between cell numbers is 1 or the width of the map in cells, the cells are directly adjacient and the distance is equal to the cell size
			distance = cellSizeKM
		elseif abs(offset - gdata.width) == 1 # If the absolute value of the distance between cell numbers minus the width of the map is 1, the cells are diagonally adjacient and teh distance is equal to the cell size times the square root of two
			distance = cellSizeKM * 2^0.5
		else # If neither of these apply, convert cell locations to latitude/longitude and calculate distance from the coordinates
			lat1, lon1 = cellToLocation(gdata, cell1)
			lat2, lon2 = cellToLocation(gdata, cell2)
			distance = calculateLatLonDistance(lat1, lon1, lat2, lon2)
		end
	else # if the projection uses unprojected decimal degrees, convert cell locations to latitude/longitude and calculate distance from the coordinates
		lat1, lon1 = cellToLocation(gdata, cell1)
		lat2, lon2 = cellToLocation(gdata, cell2)
		distance = calculateLatLonDistance(lat1, lon1, lat2, lon2)
	end
	return distance
end




"""
$(DocumentFunction.documentfunction(getPathLength;
maintext="""
Calculates the length of a path.
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"path"=>"Vector of cell IDs constituting the path")))

Returns:

- Length of path in kilometers

Examples:

```julia
SimCCSpro.getPathLength(gdata, path)
```
"""
function getPathLength(gdata::Data, path::Vector{Int64})
	length = 0.0
	node1 = path[1] # Set the first node in the path to node1
	for node2 in path[2:end] # Iterate through the rest of the nodes in the path
		length = length + getDistance(gdata, node1, node2) # Add the distance between nodes to the path length
		node1 = node2
	end
	return length
end




"""
$(DocumentFunction.documentfunction(isSourcesSinksWithinCostSurface;
maintext="""
Check whether all sources, sinks and terminals are within the cost surface
""",
argtext=Dict("gdata"=>"SimCCS data structure with all the data",
			"intermodal"=>"Is terminals/barges being used")))

Returns:

- true if all sources, sink and terminals are within the cost surface.  Otherwise, return false.

Examples:

```julia
SimCCSpro.isSourcesSinksWithinCostSurface(gdata, intermodal=true)
```
"""
function isSourcesSinksWithinCostSurface(gdata::Data; intermodal::Bool=false)
	allGood = true

	for source in gdata.sources
		# Check whether cellNum is within range or values (e.g. neighbors) for the cells are defined (if 0, means not defined)
		if (source.cellNum > gdata.allNodes) || (source.cellNum < 1) || (gdata.cellneighbors[source.cellNum] == 0)
			@error("Source $(source.facilityId) in cell $(source.cellNum) not on cost surface")
			allGood = false
		end
	end

	for sink in gdata.sinks
		if (sink.cellNum > gdata.allNodes) || (sink.cellNum < 1) || (gdata.cellneighbors[sink.cellNum] == 0)
			@error("Sink $(sink.sco2tId) in cell $(sink.cellNum) not on cost surface")
			allGood = false
		end
	end

	if intermodal
		for terminal in gdata.terminals
			if (terminal.cellNum > gdata.allNodes) || (terminal.cellNum < 1) || (gdata.cellneighbors[terminal.cellNum] == 0)
				@error("Terminal $(terminal.code) in cell $(terminal.cellNum) not on cost surface")
				allGood = false
			end
		end
	end

	return allGood
end



