function [DEM,FD,A,S]=MakeStreams(dem,threshold_area,varargin)
	% Function takes a dem and outputs the necessary base datasets for use in other TopoToolbox functions.
	% 	Input DEMs with grid resolutions (i.e. cellsizes) that are not whole numbers sometimes cause issues
	% 	in companion functions. If the provided DEM has a non-whole number for a cellsize, the code will
	% 	warn the user (but not do anything). If you want to fix the cellsize issue, you can either reproject
	% 	in a GIS program or you can use this code (with 'resample_grid' set to true) to do it for you.
	%
	% Required Inputs:
	% 	dem - either full path of dem file as either an ascii text file (recommended) or geotiff OR 
	%		a GRIDobj of a DEM
	% 	threshold_area - minimum accumulation area to define streams in meters squared
	%
	% Optional Inputs:
	%	file_name [] - name for matfile containing the DEM, FD, A, and S and the shapfile of the stream network.
	%		If file_name is not provided, the function assumes the user does not wish to save the results to a
	%		mat file (results will still appear in the workspace) or shapefile.
	%	no_data_exp [] - input to define no data conditions. Expects a string that defines a valid equality using
	%		the variable DEM OR 'auto'. E.g. if you wish to define that any elevation less that or equal to 0 should 
	%		be set to no data, you would provide 'DEM<=0' or if you wanted to set elevations less than 500 and greater  
	%		than 1000 ot no data, you would provide 'DEM<500 | DEM>1000'. If the expression is not valid the user will be
	%		warned, but the code will continue and ignore this continue. If you provide 'auto' the code will use the log 
	%		of the gradient to identify true connected flats and set these to nan. If you want more control on removing flat 
	%		ares that are at multiple elevations (e.g. internally drained basins), consider using 'RemoveFlats'. 
	%	min_flat_area [1e5] - minimum area (in m^2) for a portion of the DEM to be identified as flat (and set to nan) if 'no_data_exp'
	%		is set to 'auto'. If 'no_data_exp' is not called or a valid logical expression is provided, the input to 'min_flat_area'
	%		is ignored.
	%	resample_grid [false] - flag to resample the grid. If no input is provided for new_cellsize, then the
	%		grid will be resampled to the nearest whole number of the native cellsize.
	%	new_cellsize [] - value (in map units) for new cellsize.
	%
	% Outputs:
	% 	DEM - GRIDobj of the DEM
	% 	FD - FLOWobj from the supplied DEM
	% 	A - Flow accumulation grid (GRIDobj)
	% 	S - STREAMobj derived from the DEM
	% 
	%
	% Examples: 
	%	[DEM,FD,A,S]=MakeStreams('/Users/forte/topo/dem.tif',1e6);
	%	[DEM,FD,A,S]=MakeStreams('/Users/forte/topo/dem.tif',1e6,'file_name','AreaFiles');
	%	[DEM,FD,A,S]=MakeStreams(DEMgrid,1e6,'resample_grid',true); %Where DEMgrid is a GRIDobj	
	%	[DEM,FD,A,S]=MakeStreams('/Users/forte/topo/dem.tif',1e6,'no_data_exp','DEM<=-100 | DEM>10000'); %Set elevations
	%		below -100m or above 10,000m to nan
	% 
	%
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	% Function Written by Adam M. Forte - Last Revised Spring 2018 %
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	% Parse Inputs
	p = inputParser;         
	p.FunctionName = 'MakeStreams';
	addRequired(p,'dem',@(x) isa(x,'GRIDobj') | ischar(x));
	addRequired(p,'threshold_area', @(x) isscalar(x));

	addParamValue(p,'file_name',[],@(x) ischar(x));
	addParamValue(p,'no_data_exp',[],@(x) ischar(x));
	addParamValue(p,'min_flat_area',1e5,@(x) isnumeric(x) && isscalar(x));
	addParamValue(p,'resample_grid',false,@(x) isscalar(x) && islogical(x));
	addParamValue(p,'new_cellsize',[],@(x) isscalar(x) && isnumeric(x));

	parse(p,dem,threshold_area,varargin{:});
	dem=p.Results.dem;
	threshold_area=p.Results.threshold_area;

	file_name=p.Results.file_name;
	no_data_exp=p.Results.no_data_exp;
	min_flat_area=p.Results.min_flat_area;
	resample_grid=p.Results.resample_grid;
	new_cellsize=p.Results.new_cellsize;


	% Check for filename
	if isempty(file_name)
		save_output=false;
	else
		save_output=true;
	end

	% Check type of input
	if isa(dem,'GRIDobj');
		DEM=dem;
	elseif ischar(dem);
		disp('Loading and processing DEM')
		DEM=GRIDobj(dem);
	else
		error('Input for dem not recognized as either a GRIDobj or character')
	end

	% Resample grid if flag is thrown
	if resample_grid & isempty(new_cellsize)
		disp('Resampling DEM - May take some time, please be patient')
		DEM=resample(DEM,ceil(DEM.cellsize),'bicubic');
	elseif resample_grid & ~isempty(new_cellsize)
		disp('Resampling DEM - May take some time, please be patient')
		DEM=resample(DEM,new_cellsize,'bicubic');		
	end

	% Check resolution of DEM
	if mod(DEM.cellsize,1)~=0 & ~resample_grid
		warning('Grid Cellsize is not a whole number, this may cause problems in some TopoToolbox functions, consider using resample_grid option')
	end

	% Optional cleaning step depending on user input
	disp('Cleaning Up DEM')
	if ~isempty(no_data_exp) & ~strcmp(no_data_exp,'auto')
		try 
			IDX=eval(no_data_exp);
			DEM.Z(IDX.Z)=nan;
			% Remove any borders of nans
			DEM=crop(DEM);
		catch
			warning('Provided "no_data_exp" was not a valid expression, proceeding without this no data condition');
		end
	elseif strcmp(no_data_exp,'auto')
		[DEM]=AutoFlat(DEM,min_flat_area);
	else
		% Remove any borders of nans
		DEM=crop(DEM);
	end


	if save_output
        fileNameBase=file_name;
        MatFileName=[fileNameBase '.mat'];
        ShpFileName=[fileNameBase '.shp'];
		save(MatFileName,'DEM','-v7.3');
	end

	disp('Calculating Flow Direction')
	FD=FLOWobj(DEM,'preprocess','carve','verbose',true);

	if save_output
		save(MatFileName,'FD','-append');
	end

	disp('Calculating Flow Accumulation')
	A=flowacc(FD);

	disp('Extracting total stream network')
	DEM_res=DEM.cellsize;
	min_area=floor(threshold_area/(DEM_res*DEM_res));
	isstream=A>min_area;
	S=STREAMobj(FD,isstream);

	if save_output
		save(MatFileName,'A','S','-append');
		MS=STREAMobj2mapstruct(S);
		shapewrite(MS,ShpFileName);
	end

end

function [DEMn] = AutoFlat(DEM,min_area)

    num_pix=round(min_area/(DEM.cellsize^2));

    LG=log10(gradient8(DEM));
    BW=isnan(LG.Z) | isinf(LG.Z);
    CC=bwconncomp(BW);
    FLATS=GRIDobj(DEM,'logical');

    for ii=1:numel(CC.PixelIdxList)
        if numel(CC.PixelIdxList{ii})>=num_pix
            idx=CC.PixelIdxList{ii};
            FLATS.Z(idx)=true;
        end
    end

    DEMn=DEM;
    DEMn.Z(FLATS.Z)=nan;

end