% CarbCal.m
% Peter Carlson
% 11/29/2015

%close all
%clc


warning('off','MATLAB:codetools:ModifiedVarnames')
warning('off','MATLAB:xlswrite:AddSheet')
warning('off','MATLAB:table:ModifiedVarnames');


SetupTable = readtable('CarbCalibrationSetup.xlsx');
SetupTable = SetupTable(ismissing(SetupTable(:,1)),2:end);


%% Fixed Parameters 
%standards
NBS19d13Cact = 1.95; %PDB
NBS19d18Oact = 28.6; %SMOW
NBS18d13Cact = -5.014; %PDB
NBS18d18Oact = 7.2; %SMOW
UTMd13Cact = 4.49; %PDB
UTMd18Oact = 26.5; %SMOW

Mediand13CNBSslope = 1.0011;
Mediand18ONBSslope = 1.0011; %check if same as oxygen

%generate table for all WC data to be plotted
PlottingTable = cell2table({});
FlaggedTable = cell2table({});
PlotSTD = cell2table({});
NBS18STD = cell2table({});
NBS19STD = cell2table({});

SawtoothAdjust=-[...
    0
    0
    -0.3822
    -0.6322
    -0.3855
    -0.0222
    0.1978
    -0.1282
    0.0921
    0.4532
    1.009
    0.7320
    -0.1324
    -0.2452
    -0.2888
    -0.4022
    0.2000
    -0.8922
    0.8278];


for i = 1:1:height(SetupTable)
    clc
    Progress = strcat('[',repmat('|',1,i),repmat('-',1,height(SetupTable)-i),']')
    
    %Names listed variables
    
    Date = char(SetupTable.Date(i));
    Analyst = char(SetupTable.Analyst(i));
    ReactionTemp = double(SetupTable.ReactionTemp(i));
    ReactionTime = double(SetupTable.ReactionTime(i));
    InputExcelFile = char(SetupTable.InputExcelFile(i));
    RunLogFile = char(SetupTable.RunLogFile(i));
    Blank = char(SetupTable.Blank(i));
    Linearity = char(SetupTable.Linearity(i));
    Drift = char(SetupTable.Drift(i));
    NBS18name = char(SetupTable.NBS18name(i));
    NBS19name = char(SetupTable.NBS19name(i));
    UTMname = char(SetupTable.UTMname(i));
    Blankname = char(SetupTable.Blankname(i));
    MaxStDevd18O = double(SetupTable.MaxStDevd18O(i));
    MaxStDevd13C = double(SetupTable.MaxStDevd13C(i));
    PeaksToUse = char(SetupTable.Peak(i));


    %Read input file and generate output file 
    OutputAddendum = '-calibrated.xlsx'; %Avoids overwriting the input file
    TemplateExcelFile = 'CarbCalTemplate.xlsx'; %do not change.
    OutputExcelFile = strrep(InputExcelFile,'.xls',OutputAddendum);

    FullTable = readtable(InputExcelFile);
    copyfile(TemplateExcelFile,OutputExcelFile);
    writetable(FullTable(:,:),OutputExcelFile,'Sheet',...
        'gasbenchCO2template.wke','Range','A1');
    
    
    FullTable(:,all(ismissing(FullTable),1)) = []; %delete empty columns
    MissingRows = ismissing(FullTable);
    FullTable = FullTable(~any(MissingRows,2),:); %del rows w/empty values
    
    LogTable = readtable(RunLogFile); %Future work: allow for no log file
    writetable(LogTable(:,:),OutputExcelFile,...
        'Sheet','Run Log','Range','A1');

    %Assumes first column is row numbers, second names, third notes
    LogNotes = LogTable(:,2);


    %% Peak-counting Calibration
    
    % Remove small air peaks that show up between sample peaks.
    
    FullTable(FullTable.Area44<1,:)=[];
    
    
    % Find unique row numbers, and count how often they appear. The first 5
    % correspond to reference gas peaks. Everything after that is sample.

    [Rows, RowsIndex, ~] = unique(FullTable.Row,'stable');
    Rows = str2double(Rows);
    try
        FullTable.Row = str2double(FullTable.Row);
    catch
    end
            
    Peaks = histc(FullTable.Row,Rows)-5; %Count occurances of each row - 5
    
    % Find all blanks
    BlankidxAll = find(strcmpi(FullTable.Identifier1(RowsIndex),...
        Blankname));


    RowsidxNoBlanks = RowsIndex; %This is an index of all sample and std
    RowsidxNoBlanks(Peaks<2) = [];


    %If 2nd peak is much larger than 1st peak, delete 1st
    try
        FullTable(RowsidxNoBlanks(...
            FullTable.Area44(RowsidxNoBlanks+6)-FullTable.Area44(RowsidxNoBlanks+5)>0.5)...
            +6,:)=[];
    catch
        RowsidxNoBlanksNoLast = RowsidxNoBlanks(1:end-1);
        FullTable(RowsidxNoBlanksNoLast(...
            FullTable.Area44(RowsidxNoBlanksNoLast+6)-FullTable.Area44(RowsidxNoBlanksNoLast+5)>0.5)...
            +6,:)=[];
    end
    %Recalculate Rows+Row indices now without small overpressure peaks
    [Rows, RowsIndex, FullIndex] = unique(FullTable.Row,'stable');
    Peaks = histc(FullTable.Row,Rows)-5; %Count occurances of each row - 5
    NannedPeaks = Peaks;
    NannedPeaks(NannedPeaks<2) = nan; %ignores samples with <2 peaks
    PeaksNoBlanks=Peaks;
    PeaksNoBlanks(PeaksNoBlanks<2) = []; %ignores samples with <2 peaks
    RowsNoBlanks = Rows; %Many calibrations shouldn't use blanks/no peaks
    RowsNoBlanks(Peaks<2) = []; 
    RowsidxNoBlanks = RowsIndex; %This is an index of all sample and std
    RowsidxNoBlanks(Peaks<2) = [];    

    SinglePeak = Rows;
    SinglePeak(Peaks~=1) = [];   
    SinglePeakidx = RowsIndex;
    SinglePeakidx(Peaks~=1) = []; %We will treat samples/blanks with just
                                  %one peak separately

    LastPeakidx = RowsidxNoBlanks + 4 + PeaksNoBlanks;
    SecondToLastPeakidx = RowsidxNoBlanks + 3 + PeaksNoBlanks;



    %Combine samples and blanks in cell array
    %initialize with NaN makes for simpler recording later

    d13C = reshape([FullTable.d13C_12C(SecondToLastPeakidx),...
        FullTable.d13C_12C(LastPeakidx)], length(RowsNoBlanks), 2); %groups d13C data by sample
    d18O = reshape([FullTable.d18O_16O(SecondToLastPeakidx),...
        FullTable.d18O_16O(LastPeakidx)], length(RowsNoBlanks), 2);   

    mediand13C = NaN(length(Rows),1);
    stdevd13C = NaN(length(Rows),1);
    mediand18O = NaN(length(Rows),1);
    stdevd18O = NaN(length(Rows),1);
    Amplitude = NaN(length(Rows),1);
    Area = NaN(length(Rows),1);

    mediand13C(RowsNoBlanks) = median(d13C,2);
    stdevd13C(RowsNoBlanks) = std(d13C,0,2);
    mediand18O(RowsNoBlanks) = median(d18O,2);
    stdevd18O(RowsNoBlanks)= std(d18O,0,2);  
    Area(RowsNoBlanks) = FullTable.Area44(SecondToLastPeakidx); 
    Amplitude(RowsNoBlanks) = FullTable.Ampl44(SecondToLastPeakidx);

    %Single peak values (no stdev here)
    mediand13C(SinglePeak) = FullTable.d13C_12C(SinglePeakidx+5);
    mediand18O(SinglePeak) = FullTable.d18O_16O(SinglePeakidx+5);
    Area(SinglePeak) = FullTable.Area44(SinglePeakidx+5);
    Amplitude(SinglePeak) = FullTable.Ampl44(SinglePeakidx+5);



    PeaksUsedstr = 'Last Two';

    
    %Output table
   
    LogNotes(length(Rows)+1:end,:) = [];
    %This is the data all of the Excel calibration normally uses
    DataTable  = [FullTable(RowsIndex,{'Row','Identifier1'}),...
        array2table(Peaks,'VariableNames',{'Peaks'}),...
        array2table(Amplitude,'VariableNames',{'Amplitude'}),...
        array2table(Area,'VariableNames',{'Area'}),...
        array2table(mediand13C,'VariableNames',{'d13C'}),...
        array2table(stdevd13C,'VariableNames',{'stdev_d13C'}),...
        array2table(mediand18O,'VariableNames',{'d18O'}),...
        array2table(stdevd18O,'VariableNames',{'stdev_d18O'})];

    DataTable.Notes = LogNotes{:,1};

    
    %% Calibrate

    %Find Blanks
    Blankidx = find(strcmpi(DataTable.Identifier1,Blankname)...
        & DataTable.Peaks > 0); %only blanks with peaks
    
    % samples with non-failed stdev
    Boolmat = DataTable.stdev_d13C < MaxStDevd13C & ...
        DataTable.stdev_d18O < MaxStDevd18O; 

    NBS18idx = find(strcmpi(DataTable.Identifier1,NBS18name) & Boolmat);
    NBS19idx = find(strcmpi(DataTable.Identifier1,NBS19name) & Boolmat);
    UTMidx = find(strcmpi(DataTable.Identifier1,UTMname) & Boolmat);

    STDidx = [NBS18idx; NBS19idx; UTMidx]; %all stds with good std dev
    STDidxAll = [...
        find(strcmpi(DataTable.Identifier1,NBS18name));...
        find(strcmpi(DataTable.Identifier1,NBS19name));...
        find(strcmpi(DataTable.Identifier1,UTMname))];

    %Blank Calibration

    if strcmpi(Blank,'False') %Manually chosen no correction
        DataTable.Area_Blank_Corrected = DataTable.Area;
        DataTable.d13C_Blank_Corrected = DataTable.d13C;
        DataTable.d18O_Blank_Corrected = DataTable.d18O;
        Blank = 'No (Manual)'; %No correction applied
    elseif isempty(Blankidx) %No blanks with peaks
        DataTable.Area_Blank_Corrected = DataTable.Area;
        DataTable.d13C_Blank_Corrected = DataTable.d13C;
        DataTable.d18O_Blank_Corrected = DataTable.d18O;   
        Blank = 'No (No Peaks)'; %No correction applied
    else %Try correction
        BlankArea = nanmedian(DataTable.Area(Blankidx)); %median ignoring NaN
        Blankd13C = nanmedian(DataTable.d13C(Blankidx));
        Blankd18O = nanmedian(DataTable.d18O(Blankidx));

        %Blank Area correction: Area_sample - Area_blank
        DataTable.Area_Blank_Corrected = DataTable.Area - BlankArea;

        %Blank d13C Correction: 
        %(area_sample*d13C_sample - area_blank*d13C_blank)/area_blank
        DataTable.d13C_Blank_Corrected = (DataTable.Area_Blank_Corrected...
            .* DataTable.d13C - BlankArea * Blankd13C) ./ ...
            DataTable.Area_Blank_Corrected;

        %Blank d18O Correction: 
        %(area_sample*d18O_sample - area_blank*d18O_blank)/area_blank
        DataTable.d18O_Blank_Corrected = (DataTable.Area_Blank_Corrected...
            .* DataTable.d18O - BlankArea * Blankd18O) ./ ...
            DataTable.Area_Blank_Corrected;
    end

    if strcmpi(Blank,'Auto') %see if correction helped STD std devs
        
        CorrectedError = nanstd(DataTable.d13C_Blank_Corrected(UTMidx))...
            + nanstd(DataTable.d18O_Blank_Corrected(UTMidx));
        
        UncorrectedError = nanstd(DataTable.d13C(UTMidx)) +...
            nanstd(DataTable.d18O(UTMidx));

        if CorrectedError > UncorrectedError %If worse, back to uncorrected
            DataTable.Area_Blank_Corrected = DataTable.Area;
            DataTable.d13C_Blank_Corrected = DataTable.d13C;
            DataTable.d18O_Blank_Corrected = DataTable.d18O;
            Blank = 'No (Auto)';

        else Blank = 'Yes (Auto)';
        end
    end


    %Linearity Correction
    if strcmpi(Linearity,'False') %Manually chosen no correction

        DataTable.d13C_Linearity_Corrected = ...
            DataTable.d13C_Blank_Corrected;
        DataTable.d18O_Linearity_Corrected = ...
        DataTable.d18O_Blank_Corrected;
        Linearity = 'No (Manual)'; %No correction applied
    else
        LinC = polyfit(DataTable.Area_Blank_Corrected(UTMidx),...
            DataTable.d13C_Blank_Corrected(UTMidx),1);

        LinO = polyfit(DataTable.Area_Blank_Corrected(UTMidx),...
            DataTable.d18O_Blank_Corrected(UTMidx),1);

        DataTable.d13C_Linearity_Corrected = ...
            DataTable.d13C_Blank_Corrected - ...
            DataTable.Area_Blank_Corrected .* LinC(1);
        
        DataTable.d18O_Linearity_Corrected = ...
            DataTable.d18O_Blank_Corrected - ...
            DataTable.Area_Blank_Corrected .* LinO(1);
    end
    if strcmpi(Linearity,'Auto')

        CorrectedError = std(DataTable.d13C_Linearity_Corrected(STDidx))...
            + std(DataTable.d18O_Linearity_Corrected(STDidx));
        
        UncorrectedError = std(DataTable.d13C_Blank_Corrected(STDidx))...
            + std(DataTable.d18O_Blank_Corrected(STDidx));

        if CorrectedError > UncorrectedError
            DataTable.d13C_Linearity_Corrected = ...
                DataTable.d13C_Blank_Corrected;
            
            DataTable.d18O_Linearity_Corrected = ...
                DataTable.d18O_Blank_Corrected;
            
            Linearity = 'No (Auto)';

        else Linearity = 'Yes (Auto)';
        end

    else Linearity = 'Yes (Manual)';
    end


    %Drift Correction

    if strcmpi(Drift,'False')
        DataTable.d13C_Drift_Corrected = ...
            DataTable.d13C_Linearity_Corrected;
        
        DataTable.d18O_Drift_Corrected = ...
            DataTable.d18O_Linearity_Corrected;
        
        Drift = 'No (Manual)';
    else
        DriftC = polyfit(DataTable.Row(UTMidx),...
            DataTable.d13C_Linearity_Corrected(UTMidx),1);
        
        DriftO = polyfit(DataTable.Row(UTMidx),...
            DataTable.d18O_Linearity_Corrected(UTMidx),1);

        DataTable.d13C_Drift_Corrected = ...
            DataTable.d13C_Linearity_Corrected - ...
            (DataTable.Row-DataTable.Row(1)) .* DriftC(1);
        
        DataTable.d18O_Drift_Corrected = ...
            DataTable.d18O_Linearity_Corrected - ...
            (DataTable.Row-DataTable.Row(1)) .* DriftO(1);
    end

    if strcmpi(Drift,'Auto')

        CorrectedError = std(DataTable.d13C_Drift_Corrected(UTMidx)) + ...
        std(DataTable.d18O_Drift_Corrected(UTMidx));
    
        UncorrectedError = ...
            std(DataTable.d13C_Linearity_Corrected(UTMidx)) + ...
            std(DataTable.d18O_Linearity_Corrected(UTMidx));

        if CorrectedError > UncorrectedError
            DataTable.d13C_Drift_Corrected = ...
                DataTable.d13C_Linearity_Corrected;
            
            DataTable.d18O_Drift_Corrected = ...
                DataTable.d18O_Linearity_Corrected;
            
            Drift = 'No (Auto)';

        else Drift = 'Yes (Auto)';
        end

    else Drift = 'Yes (Manual)';
    end


    %Std Correction
    %Always do a std correction
    %Get slope from NBS, then get intercept from UTM
    
    
    %All Standards slope and intercept adjustment    
    StdC = polyfit([median(DataTable.d13C_Drift_Corrected(UTMidx)),...
        median(DataTable.d13C_Drift_Corrected(NBS18idx)), ...
        median(DataTable.d13C_Drift_Corrected(NBS19idx))], ...
        [UTMd13Cact,NBS18d13Cact,NBS19d13Cact],1);
    StdO = polyfit([median(DataTable.d18O_Drift_Corrected(UTMidx)),...
        median(DataTable.d18O_Drift_Corrected(NBS18idx)), ...
        median(DataTable.d18O_Drift_Corrected(NBS19idx))], ...
        [UTMd18Oact,NBS18d18Oact,NBS19d18Oact],1);


    DataTable.d13C_Std_Corrected = DataTable.d13C_Drift_Corrected .* ...
        StdC(1) + StdC(2);
    DataTable.d18O_Std_Corrected = DataTable.d18O_Drift_Corrected .* ...
        StdO(1) + StdO(2);

    DataTable.d13C_MedNBS_UTM_Corrected = DataTable.d13C_Drift_Corrected .* ...
        Mediand13CNBSslope;
    DataTable.d18O_MedNBS_UTM_Corrected = DataTable.d18O_Drift_Corrected .* ...
       Mediand18ONBSslope;    

    %Skip NBS, assume slope = 1, adjust to UTM
    NONBSStdC = UTMd13Cact - median(DataTable.d13C_Drift_Corrected(UTMidx));  
    NONBSStdO = UTMd18Oact - median(DataTable.d18O_Drift_Corrected(UTMidx));
    
    DataTable.d13C_NONBS_Corrected = DataTable.d13C_Drift_Corrected + ...
        NONBSStdC;
    DataTable.d18O_NONBS_Corrected = DataTable.d18O_Drift_Corrected + ...
        NONBSStdO;
    
    %Use NBS slope and intercept, then add a UTM intercept adjustment
    %(Better for d18O?)
    UTMStdC = UTMd13Cact - median(DataTable.d13C_Std_Corrected(UTMidx)); 
    UTMStdO = UTMd18Oact - median(DataTable.d18O_Std_Corrected(UTMidx));

    DataTable.d13C_UTM_Corrected = DataTable.d13C_Std_Corrected + ...
        UTMStdC;
    DataTable.d18O_UTM_Corrected = DataTable.d18O_Std_Corrected + ...
        UTMStdO;

    %Use NBS slope and intercept, then add a NBS18 intercept adjustment
    %(Better for d13C?)
    NBS18StdC = NBS18d13Cact - median(DataTable.d13C_Std_Corrected(NBS18idx)); 
    NBS18StdO = NBS18d18Oact - median(DataTable.d18O_Std_Corrected(NBS18idx));

    DataTable.d13C_NBS18_Corrected = DataTable.d13C_Std_Corrected + ...
        NBS18StdC;
    DataTable.d18O_NBS18_Corrected = DataTable.d18O_Std_Corrected + ...
        NBS18StdO;
   
    %Use average NBS slope and intercept, then add a NBS18 intercept adjustment

    DataTable.d13C_MedNBS_18_Corrected = DataTable.d13C_MedNBS_UTM_Corrected + ...
        NBS18d13Cact - median(DataTable.d13C_MedNBS_UTM_Corrected(NBS18idx));
    DataTable.d18O_MedNBS_18_Corrected = DataTable.d18O_MedNBS_UTM_Corrected + ...
        NBS18d18Oact - median(DataTable.d18O_MedNBS_UTM_Corrected(NBS18idx));
    
    DataTable.d13C_sawtooth = DataTable.d13C_MedNBS_18_Corrected + SawtoothAdjust(i);
    
    %Use average NBS slope and intercept, then add a UTM intercept adjustment

    DataTable.d13C_MedNBS_UTM_Corrected = DataTable.d13C_MedNBS_UTM_Corrected + ...
        UTMd13Cact - median(DataTable.d13C_MedNBS_UTM_Corrected(UTMidx));
    DataTable.d18O_MedNBS_UTM_Corrected = DataTable.d18O_MedNBS_UTM_Corrected + ...
        UTMd18Oact - median(DataTable.d18O_MedNBS_UTM_Corrected(UTMidx));
    
    
    %% Calibration Data Export
    %Printing to Excel Calibration sheet so all calibrations are clear
    
    %Table of Meta-info
    Values = {Date;Analyst};
    InfoTable = table(Values);

    writetable(InfoTable,OutputExcelFile,'Sheet','Calibration','Range',...
        'E3','WriteVariableNames',false);


    %Table of Calibration Information
    CorrectionApplied = {MaxStDevd13C; MaxStDevd18O; PeaksUsedstr;...
        Blank; Linearity; Drift};
    CalTable = table(CorrectionApplied);
    writetable(CalTable,OutputExcelFile,'Sheet','Calibration','Range',...
        'E7','WriteVariableNames',false);

    %Data Table
    writetable(DataTable(:,{'Row','Identifier1','Amplitude','Area',...
        'd13C','d18O','stdev_d13C','stdev_d18O'}),OutputExcelFile,...
        'Sheet','Calibration','Range','B32','WriteVariableNames',false);

    %Blank Table
    if Blankidx
        writetable(DataTable(Blankidx,{'Row','Identifier1','Amplitude',...
            'Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
            OutputExcelFile,'Sheet','Calibration','Range','B134',...
            'WriteVariableNames',false);
    end

    %UTM Table
    writetable(DataTable(UTMidx,{'Row','Identifier1','Amplitude','Area',...
        'd13C','d18O','stdev_d13C','stdev_d18O'}),OutputExcelFile,...
        'Sheet','Calibration','Range','B144','WriteVariableNames',false);

    %NBS-18 Table
    writetable(DataTable(NBS18idx,{'Row','Identifier1','Amplitude',...
        'Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
        OutputExcelFile,'Sheet','Calibration','Range','B174',...
        'WriteVariableNames',false);


    %NBS-19 Table
    writetable(DataTable(NBS19idx,{'Row','Identifier1','Amplitude',...
        'Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
        OutputExcelFile,'Sheet','Calibration','Range','B184',...
        'WriteVariableNames',false);


    %% Data Export
    % Exported Data should have no links


    d13CError = std(DataTable.d13C_Std_Corrected(UTMidx));
    d18OVPDBError = std((DataTable.d18O_Std_Corrected(UTMidx)-30.91)...
        ./ 1.03091);

    ExportTable = DataTable(:,{'Row','Identifier1','Notes',...
        'Area_Blank_Corrected','d13C_Std_Corrected', 'd13C_UTM_Corrected', 'd13C_NONBS_Corrected','d13C_NBS18_Corrected','d13C_MedNBS_18_Corrected','d13C_MedNBS_UTM_Corrected','d13C_sawtooth'...
        'd18O_Std_Corrected', 'd18O_UTM_Corrected', 'd18O_NONBS_Corrected','d18O_NBS18_Corrected','stdev_d18O','stdev_d13C'});
    ExportTable([BlankidxAll; STDidxAll],:) = [];
    ExportTable.d18O_VPDB = (ExportTable.d18O_UTM_Corrected-30.91)/1.03091;
    ExportTable.d18O_VPDB_NONBS = (ExportTable.d18O_NONBS_Corrected-30.91)/1.03091;
    ExportTable(ExportTable.stdev_d18O>MaxStDevd18O,:) = [];
    ExportTable(ExportTable.stdev_d13C>MaxStDevd13C,:) = [];
    ExportTable.d13C_Error = d13CError.*ones(height(ExportTable),1);
    ExportTable.d18O_Error = d18OVPDBError.*ones(height(ExportTable),1);
    ExportTable.Date = repmat({Date},[height(ExportTable),1]);
    ExportTable.Analyst = repmat({Analyst},[height(ExportTable),1]);
    ExportTable.Reaction_Time = ReactionTime*ones(height(ExportTable),1);
    ExportTable.Reaction_Temp = ReactionTemp*ones(height(ExportTable),1);
    ExportTable.i = i*ones(height(ExportTable),1);

    writetable(ExportTable(:,{'Identifier1','Date','Row'}),...
        OutputExcelFile,'Sheet','Data Export','Range','A2',...
        'WriteVariableNames',false);
    writetable(ExportTable(:,{'Area_Blank_Corrected',...
        'd13C_UTM_Corrected','d13C_Error','d18O_UTM_Corrected',...
        'd18O_Error','Analyst'}),OutputExcelFile,'Sheet','Data Export',...
        'Range','H2','WriteVariableNames',false);
    writetable(ExportTable(:,{'Reaction_Temp','Reaction_Time','Notes'}),...
        OutputExcelFile,'Sheet','Data Export','Range','O2',...
        'WriteVariableNames',false);
    
    PlottingTable = [PlottingTable; ExportTable(:,...
        {'Identifier1', 'd18O_Std_Corrected', 'd18O_UTM_Corrected', 'd18O_NONBS_Corrected','d18O_Error',...
        'd13C_Std_Corrected', 'd13C_UTM_Corrected', 'd13C_NONBS_Corrected','d13C_NBS18_Corrected','d13C_MedNBS_18_Corrected','d13C_MedNBS_UTM_Corrected','d13C_sawtooth','d13C_Error','i'})];

    % Flag any areas that are smaller than the smallest used UTM standard 
    MinStdArea = min(table2array(DataTable(UTMidx,{'Area'})));
    
    Flagidx = find(ExportTable.Area_Blank_Corrected < MinStdArea); %only blanks with peaks
    FlaggedTable = [FlaggedTable; ExportTable(Flagidx,...
        {'Identifier1', 'd18O_VPDB','d18O_Error',...
        'd13C_UTM_Corrected', 'd13C_Error'})];
    
    DataTable.Date = repmat({Date},[height(DataTable),1]);
    DataTable.i = ones(height(DataTable),1)*i;
    DataTable.slope = ones(height(DataTable),1)*StdC(1);
    DataTable.intercept = ones(height(DataTable),1)*StdC(2);
    DataTable.UTMadjust = ones(height(DataTable),1)*UTMStdC;
    DataTable.d13CError = ones(height(DataTable),1)*d13CError;
    
    PlotSTD = [PlotSTD; DataTable(UTMidx,{'d13C_sawtooth', 'd13C_Std_Corrected', 'd13C_UTM_Corrected', 'd13C_NONBS_Corrected','d13C_NBS18_Corrected','d13C', 'Area', 'd13CError', 'Date','i'})];
    NBS18STD = [NBS18STD; DataTable(NBS18idx,{'d13C_sawtooth', 'd13C_Std_Corrected', 'd13C_UTM_Corrected', 'd13C_NONBS_Corrected','d13C_NBS18_Corrected','d13C', 'd13CError', 'slope','intercept','UTMadjust','Area', 'Date','i'})];
    NBS19STD = [NBS19STD; DataTable(NBS19idx,{'d13C_sawtooth', 'd13C_Std_Corrected', 'd13C_UTM_Corrected','d13C_NONBS_Corrected','d13C_NBS18_Corrected', 'd13C', 'd13CError', 'slope','intercept','UTMadjust', 'Area', 'Date','i'})];
end
%% plotting things - Not part of calibration. Just me making sure it worked
%{
close all
UTM_adjust_sawtooth = UTMd13Cact - median(PlotSTD{:,1})
stdevSTD = std(PlotSTD{:,1});
stdevUTM = std(PlotSTD{:,2});
stdevNONBS = std(PlotSTD{:,3});



PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,...
    'WC-3','WC3');
FlaggedTable.Identifier1 = regexprep(FlaggedTable.Identifier1,...
    'WC-3','WC3');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,...
    'WC 3','WC3');
FlaggedTable.Identifier1 = regexprep(FlaggedTable.Identifier1,...
    'WC 3','WC3');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,...
    ' new','');
FlaggedTable.Identifier1 = regexprep(FlaggedTable.Identifier1,...
    ' new','');
NanData = ismissing(PlottingTable);
NanFlag = ismissing(FlaggedTable);
PlottingTable = PlottingTable(~any(NanData,2),:);
FlaggedTable = FlaggedTable(~any(NanFlag,2),:);

PlottingTable(~strncmpi('WC3',PlottingTable.Identifier1(:),3),:)=[];
FlaggedTable(~strncmpi('WC3',FlaggedTable.Identifier1(:),3),:)=[];
PlottingTable.DrillSpot = zeros(height(PlottingTable),1);
FlaggedTable.DrillSpot = zeros(height(FlaggedTable),1);
for i = 1:height(PlottingTable)
    ID = strsplit(PlottingTable.Identifier1{i});
    PlottingTable.DrillSpot(i) = str2double(ID{:,2});
end

for i = 1:height(FlaggedTable)
    ID = strsplit(FlaggedTable.Identifier1{i});
    FlaggedTable.DrillSpot(i) = str2double(ID{:,2});
end

PlottingTable = sortrows(PlottingTable,{'DrillSpot'},{'ascend'});
FlaggedTable = sortrows(FlaggedTable,{'DrillSpot'},{'ascend'});



startone = [1,10];
endone = [250,6.4];
starttwo = [251,endone(2)+0.15];
endtwo = [300,starttwo(2)-50*0.0125];
startthree = [301,endtwo(2)+0.23];
endthree = [410,startthree(2)-110*0.0125];
startfour = [411,endthree(2)+0.15];
endfive = [824,0];
startsix = [1001,9.05];
endsix = [1029,8.65];

PlottingTable.Distance = zeros(height(PlottingTable),1);
FlaggedTable.Distance = zeros(height(FlaggedTable),1);

for i = 1:height(PlottingTable)
    if(PlottingTable.DrillSpot(i)<=endone(1))
        PlottingTable.Distance(i) = (endone(2)-startone(2))/(endone(1)-startone(1))*(PlottingTable.DrillSpot(i)-startone(1)) +startone(2);
        breakone=i;
        
    elseif(PlottingTable.DrillSpot(i)<=endtwo(1))
        PlottingTable.Distance(i) = (endtwo(2)-starttwo(2))/(endtwo(1)-starttwo(1))*(PlottingTable.DrillSpot(i)-starttwo(1)) +starttwo(2);
        breaktwo=i;
        
    elseif(PlottingTable.DrillSpot(i)<=endthree(1))
        
        PlottingTable.Distance(i) = (endthree(2)-startthree(2))/(endthree(1)-startthree(1))*(PlottingTable.DrillSpot(i)-startthree(1)) +startthree(2);
        breakthree=i;
        
    elseif(PlottingTable.DrillSpot(i)<=endfive(1))
        PlottingTable.Distance(i) = (endfive(2)-startfour(2))/(endfive(1)-startfour(1))*(PlottingTable.DrillSpot(i)-startfour(1)) +startfour(2);
        breakfour=i;
       
    else
        PlottingTable.Distance(i) = (endsix(2)-startsix(2))/(endsix(1)-startsix(1))*(PlottingTable.DrillSpot(i)-startsix(1)) +startsix(2);
    end         
end

for i = 1:height(FlaggedTable)
    if(FlaggedTable.DrillSpot(i)<=endone(1))
        FlaggedTable.Distance(i) = (endone(2)-startone(2))/(endone(1)-startone(1))*(FlaggedTable.DrillSpot(i)-startone(1)) +startone(2);
    elseif(FlaggedTable.DrillSpot(i)<=endtwo(1))
        FlaggedTable.Distance(i) = (endtwo(2)-starttwo(2))/(endtwo(1)-starttwo(1))*(FlaggedTable.DrillSpot(i)-starttwo(1)) +starttwo(2);       
    elseif(FlaggedTable.DrillSpot(i)<=endthree(1))
        FlaggedTable.Distance(i) = (endthree(2)-startthree(2))/(endthree(1)-startthree(1))*(FlaggedTable.DrillSpot(i)-startthree(1)) +startthree(2);
    elseif(FlaggedTable.DrillSpot(i)<=endfive(1))
        FlaggedTable.Distance(i) = (endfive(2)-startfour(2))/(endfive(1)-startfour(1))*(FlaggedTable.DrillSpot(i)-startfour(1)) +startfour(2);
    else
        FlaggedTable.Distance(i) = (endsix(2)-startsix(2))/(endsix(1)-startsix(1))*(FlaggedTable.DrillSpot(i)-startsix(1)) +startsix(2);
    end         
end

d13CSTDSmoothness = sum((PlottingTable.d13C_Std_Corrected(1:end-1) - PlottingTable.d13C_Std_Corrected(2:end)).^2)
d13CUTMSmoothness = sum((PlottingTable.d13C_UTM_Corrected(1:end-1) - PlottingTable.d13C_UTM_Corrected(2:end)).^2)
d13CNONBSSmoothness = sum((PlottingTable.d13C_NONBS_Corrected(1:end-1) - PlottingTable.d13C_NONBS_Corrected(2:end)).^2)
d13CNBS18Smoothness = sum((PlottingTable.d13C_NBS18_Corrected(1:end-1) - PlottingTable.d13C_NBS18_Corrected(2:end)).^2)
d13CMedNBSSmoothness = sum((PlottingTable.d13C_MedNBS_18_Corrected(1:end-1) - PlottingTable.d13C_MedNBS_18_Corrected(2:end)).^2)
d13CMedNBSUTMSmoothness = sum((PlottingTable.d13C_MedNBS_UTM_Corrected(1:end-1) - PlottingTable.d13C_MedNBS_UTM_Corrected(2:end)).^2)
d13CSawtoothSmoothness = sum((PlottingTable.d13C_sawtooth(1:end-1) - PlottingTable.d13C_sawtooth(2:end)).^2)


scrnsz = get(groot, 'ScreenSize');
Font = 14;

%{
%d18O chunks 1
figure('Position', [1,scrnsz(4)/2,scrnsz(3),scrnsz(4)/2]);
hold on;
plot(PlottingTable.Distance(1:breakone), PlottingTable.d18O_VPDB(1:breakone),'k',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d18O_VPDB(breaktwo+1:breakthree),'k')

p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d18O_VPDB(1:breakone) + PlottingTable.d18O_Error(1:breakone);...
    flipud(PlottingTable.d18O_VPDB(1:breakone) - ...
    PlottingTable.d18O_Error(1:breakone))],[0.5, 0.5, 0.5]);

r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d18O_VPDB(breaktwo+1:breakthree) + PlottingTable.d18O_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d18O_VPDB(breaktwo+1:breakthree) - ...
    PlottingTable.d18O_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);


set(r, 'EdgeColor','none');
set(p, 'EdgeColor','none');

alpha(0.5);
xlabel('Distance from Speleothem Top in cm','FontSize', Font);
ylabel('\delta^{18}O VPDB','FontSize', Font);
set(gca,'YLim', [-7 -2],'XLim',[0 10],'FontSize', Font, 'YAxisLocation', 'left');
hold off;


%d18O chunks 2
figure('Position', [1,scrnsz(4)/2,scrnsz(3),scrnsz(4)/2]);
hold on;
plot(PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d18O_VPDB(breakone+1:breaktwo),'k',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d18O_VPDB(breakthree+1:breakfour),'k',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d18O_VPDB(breakfour+1:end),'k')
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d18O_VPDB(breakone+1:breaktwo) + PlottingTable.d18O_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d18O_VPDB(breakone+1:breaktwo) - ...
    PlottingTable.d18O_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d18O_VPDB(breakthree+1:breakfour) + PlottingTable.d18O_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d18O_VPDB(breakthree+1:breakfour) - ...
    PlottingTable.d18O_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d18O_VPDB(breakfour+1:end) + PlottingTable.d18O_Error(breakfour+1:end);...
    flipud(PlottingTable.d18O_VPDB(breakfour+1:end) - ...
    PlottingTable.d18O_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(q, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');
alpha(0.5);
xlabel('Distance from Speleothem Top in cm','FontSize', Font);
ylabel('\delta^{18}O VPDB','FontSize', Font);
set(gca,'YLim', [-7 -2],'XLim',[0 10] ,'FontSize', Font, 'YAxisLocation', 'right');
hold off;
%}

%d18O NBS Slope and Intercept
%{
figure('Position', [1,scrnsz(4)/2,scrnsz(3),scrnsz(4)/2]);
hold on;

plot(PlottingTable.Distance(1:breakone), PlottingTable.d18O_Std_Corrected(1:breakone),'k',...
    PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d18O_Std_Corrected(breakone+1:breaktwo),'g',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d18O_Std_Corrected(breaktwo+1:breakthree),'r',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d18O_Std_Corrected(breakthree+1:breakfour),'b',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d18O_Std_Corrected(breakfour+1:end),'y')
p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d18O_Std_Corrected(1:breakone) + PlottingTable.d18O_Error(1:breakone);...
    flipud(PlottingTable.d18O_Std_Corrected(1:breakone) - ...
    PlottingTable.d18O_Error(1:breakone))],[0.5, 0.5, 0.5]);
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d18O_Std_Corrected(breakone+1:breaktwo) + PlottingTable.d18O_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d18O_Std_Corrected(breakone+1:breaktwo) - ...
    PlottingTable.d18O_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d18O_Std_Corrected(breaktwo+1:breakthree) + PlottingTable.d18O_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d18O_Std_Corrected(breaktwo+1:breakthree) - ...
    PlottingTable.d18O_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d18O_Std_Corrected(breakthree+1:breakfour) + PlottingTable.d18O_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d18O_Std_Corrected(breakthree+1:breakfour) - ...
    PlottingTable.d18O_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d18O_Std_Corrected(breakfour+1:end) + PlottingTable.d18O_Error(breakfour+1:end);...
    flipud(PlottingTable.d18O_Std_Corrected(breakfour+1:end) - ...
    PlottingTable.d18O_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(p, 'EdgeColor','none');
set(q, 'EdgeColor','none');
set(r, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');
alpha(0.5);
xlabel('Distance from Speleothem Top in cm','FontSize', Font);
ylabel('\delta^{18}O VPDB','FontSize', Font);
axis([0 10 24 29]);
title('NBS slope and intercept calibration');
hold off;

%}


%{
%d13C  NBS Slope and Intercept

figure('Position', [1,1,scrnsz(3),scrnsz(4)/2]);
hold on;
plot(PlottingTable.Distance(1:breakone), PlottingTable.d13C_Std_Corrected(1:breakone),'k',...
    PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d13C_Std_Corrected(breakone+1:breaktwo),'g',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d13C_Std_Corrected(breaktwo+1:breakthree),'r',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d13C_Std_Corrected(breakthree+1:breakfour),'b',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d13C_Std_Corrected(breakfour+1:end),'y');

p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d13C_Std_Corrected(1:breakone) + PlottingTable.d13C_Error(1:breakone);...
    flipud(PlottingTable.d13C_Std_Corrected(1:breakone) - ...
    PlottingTable.d13C_Error(1:breakone))],[0.5, 0.5, 0.5]);
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d13C_Std_Corrected(breakone+1:breaktwo) + PlottingTable.d13C_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d13C_Std_Corrected(breakone+1:breaktwo) - ...
    PlottingTable.d13C_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d13C_Std_Corrected(breaktwo+1:breakthree) + PlottingTable.d13C_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d13C_Std_Corrected(breaktwo+1:breakthree) - ...
    PlottingTable.d13C_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d13C_Std_Corrected(breakthree+1:breakfour) + PlottingTable.d13C_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d13C_Std_Corrected(breakthree+1:breakfour) - ...
    PlottingTable.d13C_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d13C_Std_Corrected(breakfour+1:end) + PlottingTable.d13C_Error(breakfour+1:end);...
    flipud(PlottingTable.d13C_Std_Corrected(breakfour+1:end) - ...
    PlottingTable.d13C_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(p, 'EdgeColor','none');
set(q, 'EdgeColor','none');
set(r, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');

alpha(0.5);

axis([0 10 -15 0]);
xlabel('WC sample order Base to top');
ylabel('\delta^{13}C VPDB');
title('NBS slope and intercept calibration');
hold off;
%}
%d18O NBS Slope and UTM Intercept
%{
figure('Position', [1,scrnsz(4)/2,scrnsz(3),scrnsz(4)/2]);
hold on;

plot(PlottingTable.Distance(1:breakone), PlottingTable.d18O_UTM_Corrected(1:breakone),'k',...
    PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d18O_UTM_Corrected(breakone+1:breaktwo),'g',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d18O_UTM_Corrected(breaktwo+1:breakthree),'r',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d18O_UTM_Corrected(breakthree+1:breakfour),'b',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d18O_UTM_Corrected(breakfour+1:end),'y')
p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d18O_UTM_Corrected(1:breakone) + PlottingTable.d18O_Error(1:breakone);...
    flipud(PlottingTable.d18O_UTM_Corrected(1:breakone) - ...
    PlottingTable.d18O_Error(1:breakone))],[0.5, 0.5, 0.5]);
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d18O_UTM_Corrected(breakone+1:breaktwo) + PlottingTable.d18O_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d18O_UTM_Corrected(breakone+1:breaktwo) - ...
    PlottingTable.d18O_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d18O_UTM_Corrected(breaktwo+1:breakthree) + PlottingTable.d18O_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d18O_UTM_Corrected(breaktwo+1:breakthree) - ...
    PlottingTable.d18O_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d18O_UTM_Corrected(breakthree+1:breakfour) + PlottingTable.d18O_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d18O_UTM_Corrected(breakthree+1:breakfour) - ...
    PlottingTable.d18O_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d18O_UTM_Corrected(breakfour+1:end) + PlottingTable.d18O_Error(breakfour+1:end);...
    flipud(PlottingTable.d18O_UTM_Corrected(breakfour+1:end) - ...
    PlottingTable.d18O_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(p, 'EdgeColor','none');

set(q, 'EdgeColor','none');
set(r, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');
alpha(0.5);
xlabel('Distance from Speleothem Top in cm','FontSize', Font);
ylabel('\delta^{18}O VPDB','FontSize', Font);
axis([0 10 24 29]);
title('NBS slope and UTM intercept calibration');
hold off;


%}

%d13C  NBS Slope and UTM Intercept
%{
figure('Position', [1,1,scrnsz(3),scrnsz(4)/2]);
hold on;
plot(PlottingTable.Distance(1:breakone), PlottingTable.d13C_UTM_Corrected(1:breakone),'k',...
    PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d13C_UTM_Corrected(breakone+1:breaktwo),'g',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d13C_UTM_Corrected(breaktwo+1:breakthree),'r',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d13C_UTM_Corrected(breakthree+1:breakfour),'b',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d13C_UTM_Corrected(breakfour+1:end),'y');

p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d13C_UTM_Corrected(1:breakone) + PlottingTable.d13C_Error(1:breakone);...
    flipud(PlottingTable.d13C_UTM_Corrected(1:breakone) - ...
    PlottingTable.d13C_Error(1:breakone))],[0.5, 0.5, 0.5]);
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d13C_UTM_Corrected(breakone+1:breaktwo) + PlottingTable.d13C_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d13C_UTM_Corrected(breakone+1:breaktwo) - ...
    PlottingTable.d13C_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d13C_UTM_Corrected(breaktwo+1:breakthree) + PlottingTable.d13C_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d13C_UTM_Corrected(breaktwo+1:breakthree) - ...
    PlottingTable.d13C_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d13C_UTM_Corrected(breakthree+1:breakfour) + PlottingTable.d13C_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d13C_UTM_Corrected(breakthree+1:breakfour) - ...
    PlottingTable.d13C_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d13C_UTM_Corrected(breakfour+1:end) + PlottingTable.d13C_Error(breakfour+1:end);...
    flipud(PlottingTable.d13C_UTM_Corrected(breakfour+1:end) - ...
    PlottingTable.d13C_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(p, 'EdgeColor','none');
set(q, 'EdgeColor','none');
set(r, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');

alpha(0.5);

axis([0 10 -15 0]);
xlabel('WC sample order Base to top');
ylabel('\delta^{13}C VPDB');
title('NBS slope and UTM intercept calibration');
hold off;
%}
%d18O 1:1 Slope and UTM Intercept
%{
figure('Position', [1,scrnsz(4)/2,scrnsz(3),scrnsz(4)/2]);
hold on;

plot(PlottingTable.Distance(1:breakone), PlottingTable.d18O_NONBS_Corrected(1:breakone),'k',...
    PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d18O_NONBS_Corrected(breakone+1:breaktwo),'g',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d18O_NONBS_Corrected(breaktwo+1:breakthree),'r',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d18O_NONBS_Corrected(breakthree+1:breakfour),'b',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d18O_NONBS_Corrected(breakfour+1:end),'y')
p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d18O_NONBS_Corrected(1:breakone) + PlottingTable.d18O_Error(1:breakone);...
    flipud(PlottingTable.d18O_NONBS_Corrected(1:breakone) - ...
    PlottingTable.d18O_Error(1:breakone))],[0.5, 0.5, 0.5]);
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d18O_NONBS_Corrected(breakone+1:breaktwo) + PlottingTable.d18O_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d18O_NONBS_Corrected(breakone+1:breaktwo) - ...
    PlottingTable.d18O_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d18O_NONBS_Corrected(breaktwo+1:breakthree) + PlottingTable.d18O_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d18O_NONBS_Corrected(breaktwo+1:breakthree) - ...
    PlottingTable.d18O_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d18O_NONBS_Corrected(breakthree+1:breakfour) + PlottingTable.d18O_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d18O_NONBS_Corrected(breakthree+1:breakfour) - ...
    PlottingTable.d18O_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d18O_NONBS_Corrected(breakfour+1:end) + PlottingTable.d18O_Error(breakfour+1:end);...
    flipud(PlottingTable.d18O_NONBS_Corrected(breakfour+1:end) - ...
    PlottingTable.d18O_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(p, 'EdgeColor','none');
set(q, 'EdgeColor','none');
set(r, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');
alpha(0.5);
xlabel('Distance from Speleothem Top in cm','FontSize', Font);
ylabel('\delta^{18}O VPDB','FontSize', Font);
axis([0 10 24 29]);
title('1:1 slope and UTM intercept calibration');
hold off;

%}

%{
%d13C  1:1 Slope and UTM Intercept

figure('Position', [1,1,scrnsz(3),scrnsz(4)/2]);
hold on;
plot(PlottingTable.Distance(1:breakone), PlottingTable.d13C_NONBS_Corrected(1:breakone),'k',...
    PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d13C_NONBS_Corrected(breakone+1:breaktwo),'g',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d13C_NONBS_Corrected(breaktwo+1:breakthree),'r',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d13C_NONBS_Corrected(breakthree+1:breakfour),'b',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d13C_NONBS_Corrected(breakfour+1:end),'y');

p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d13C_NONBS_Corrected(1:breakone) + PlottingTable.d13C_Error(1:breakone);...
    flipud(PlottingTable.d13C_NONBS_Corrected(1:breakone) - ...
    PlottingTable.d13C_Error(1:breakone))],[0.5, 0.5, 0.5]);
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d13C_NONBS_Corrected(breakone+1:breaktwo) + PlottingTable.d13C_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d13C_NONBS_Corrected(breakone+1:breaktwo) - ...
    PlottingTable.d13C_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d13C_NONBS_Corrected(breaktwo+1:breakthree) + PlottingTable.d13C_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d13C_NONBS_Corrected(breaktwo+1:breakthree) - ...
    PlottingTable.d13C_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d13C_NONBS_Corrected(breakthree+1:breakfour) + PlottingTable.d13C_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d13C_NONBS_Corrected(breakthree+1:breakfour) - ...
    PlottingTable.d13C_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d13C_NONBS_Corrected(breakfour+1:end) + PlottingTable.d13C_Error(breakfour+1:end);...
    flipud(PlottingTable.d13C_NONBS_Corrected(breakfour+1:end) - ...
    PlottingTable.d13C_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(p, 'EdgeColor','none');
set(q, 'EdgeColor','none');
set(r, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');

alpha(0.5);

axis([0 10 -15 0]);
xlabel('WC sample order Base to top');
ylabel('\delta^{13}C VPDB');
title('1:1 slope and UTM intercept calibration');
hold off;

%}
%d18O NBS Slope and NBS18 Intercept
%{
figure('Position', [1,scrnsz(4)/2,scrnsz(3),scrnsz(4)/2]);
hold on;

plot(PlottingTable.Distance(1:breakone), PlottingTable.d18O_NBS18_Corrected(1:breakone),'k',...
    PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d18O_NBS18_Corrected(breakone+1:breaktwo),'g',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d18O_NBS18_Corrected(breaktwo+1:breakthree),'r',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d18O_NBS18_Corrected(breakthree+1:breakfour),'b',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d18O_NBS18_Corrected(breakfour+1:end),'y')
p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d18O_NBS18_Corrected(1:breakone) + PlottingTable.d18O_Error(1:breakone);...
    flipud(PlottingTable.d18O_NBS18_Corrected(1:breakone) - ...
    PlottingTable.d18O_Error(1:breakone))],[0.5, 0.5, 0.5]);
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d18O_NBS18_Corrected(breakone+1:breaktwo) + PlottingTable.d18O_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d18O_NONBS_Corrected(breakone+1:breaktwo) - ...
    PlottingTable.d18O_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d18O_NBS18_Corrected(breaktwo+1:breakthree) + PlottingTable.d18O_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d18O_NBS18_Corrected(breaktwo+1:breakthree) - ...
    PlottingTable.d18O_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d18O_NBS18_Corrected(breakthree+1:breakfour) + PlottingTable.d18O_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d18O_NBS18_Corrected(breakthree+1:breakfour) - ...
    PlottingTable.d18O_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d18O_NBS18_Corrected(breakfour+1:end) + PlottingTable.d18O_Error(breakfour+1:end);...
    flipud(PlottingTable.d18O_NBS18_Corrected(breakfour+1:end) - ...
    PlottingTable.d18O_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(p, 'EdgeColor','none');
set(q, 'EdgeColor','none');
set(r, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');
alpha(0.5);
xlabel('Distance from Speleothem Top in cm','FontSize', Font);
ylabel('\delta^{18}O VPDB','FontSize', Font);
axis([0 10 24 29]);
title('NBS slope and NBS18 intercept calibration');
hold off;

%}


%d13C  NBS Slope and NBS18 Intercept
%{
figure('Position', [1,1,scrnsz(3),scrnsz(4)/2]);
hold on;
plot(PlottingTable.Distance(1:breakone), PlottingTable.d13C_NBS18_Corrected(1:breakone),'k',...
    PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d13C_NBS18_Corrected(breakone+1:breaktwo),'g',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d13C_NBS18_Corrected(breaktwo+1:breakthree),'r',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d13C_NBS18_Corrected(breakthree+1:breakfour),'b',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d13C_NBS18_Corrected(breakfour+1:end),'y');

p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d13C_NBS18_Corrected(1:breakone) + PlottingTable.d13C_Error(1:breakone);...
    flipud(PlottingTable.d13C_NBS18_Corrected(1:breakone) - ...
    PlottingTable.d13C_Error(1:breakone))],[0.5, 0.5, 0.5]);
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d13C_NBS18_Corrected(breakone+1:breaktwo) + PlottingTable.d13C_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d13C_NBS18_Corrected(breakone+1:breaktwo) - ...
    PlottingTable.d13C_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d13C_NBS18_Corrected(breaktwo+1:breakthree) + PlottingTable.d13C_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d13C_NBS18_Corrected(breaktwo+1:breakthree) - ...
    PlottingTable.d13C_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d13C_NBS18_Corrected(breakthree+1:breakfour) + PlottingTable.d13C_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d13C_NBS18_Corrected(breakthree+1:breakfour) - ...
    PlottingTable.d13C_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d13C_NBS18_Corrected(breakfour+1:end) + PlottingTable.d13C_Error(breakfour+1:end);...
    flipud(PlottingTable.d13C_NBS18_Corrected(breakfour+1:end) - ...
    PlottingTable.d13C_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(p, 'EdgeColor','none');
set(q, 'EdgeColor','none');
set(r, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');

alpha(0.5);

axis([0 10 -15 0]);
xlabel('WC sample order Base to top');
ylabel('\delta^{13}C VPDB');
title('NBS slope and NBS18 intercept calibration');
hold off;


%d13C median NBS Slope and NBS18 Intercept

figure('Position', [1,1,scrnsz(3),scrnsz(4)/2]);
hold on;
plot(PlottingTable.Distance(1:breakone), PlottingTable.d13C_MedNBS_18_Corrected(1:breakone),'k',...
    PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d13C_MedNBS_18_Corrected(breakone+1:breaktwo),'g',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d13C_MedNBS_18_Corrected(breaktwo+1:breakthree),'r',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d13C_MedNBS_18_Corrected(breakthree+1:breakfour),'b',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d13C_MedNBS_18_Corrected(breakfour+1:end),'y',...
    PlottingTable.Distance(:),-PlottingTable.i(:),'k.');
p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d13C_MedNBS_18_Corrected(1:breakone) + PlottingTable.d13C_Error(1:breakone);...
    flipud(PlottingTable.d13C_MedNBS_18_Corrected(1:breakone) - ...
    PlottingTable.d13C_Error(1:breakone))],[0.5, 0.5, 0.5]);
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d13C_MedNBS_18_Corrected(breakone+1:breaktwo) + PlottingTable.d13C_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d13C_MedNBS_18_Corrected(breakone+1:breaktwo) - ...
    PlottingTable.d13C_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d13C_MedNBS_18_Corrected(breaktwo+1:breakthree) + PlottingTable.d13C_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d13C_MedNBS_18_Corrected(breaktwo+1:breakthree) - ...
    PlottingTable.d13C_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d13C_MedNBS_18_Corrected(breakthree+1:breakfour) + PlottingTable.d13C_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d13C_MedNBS_18_Corrected(breakthree+1:breakfour) - ...
    PlottingTable.d13C_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d13C_MedNBS_18_Corrected(breakfour+1:end) + PlottingTable.d13C_Error(breakfour+1:end);...
    flipud(PlottingTable.d13C_MedNBS_18_Corrected(breakfour+1:end) - ...
    PlottingTable.d13C_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(p, 'EdgeColor','none');
set(q, 'EdgeColor','none');
set(r, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');

alpha(0.5);

axis([0 10 -20 0]);
xlabel('WC sample order Base to top');
ylabel('\delta^{13}C VPDB');
title('Median NBS slope and NBS18 intercept calibration');
hold off;
%}
%d13C median NBS Slope and sawtooth adjustment

figure('Position', [1,1,scrnsz(3),scrnsz(4)/2]);
hold on;
plot(PlottingTable.Distance(1:breakone), PlottingTable.d13C_sawtooth(1:breakone),'k',...
    PlottingTable.Distance(breakone+1:breaktwo), PlottingTable.d13C_sawtooth(breakone+1:breaktwo),'g',...
    PlottingTable.Distance(breaktwo+1:breakthree), PlottingTable.d13C_sawtooth(breaktwo+1:breakthree),'r',...
    PlottingTable.Distance(breakthree+1:breakfour), PlottingTable.d13C_sawtooth(breakthree+1:breakfour),'b',...
    PlottingTable.Distance(breakfour+1:end), PlottingTable.d13C_sawtooth(breakfour+1:end),'y',...
    PlottingTable.Distance(:),-PlottingTable.i(:),'k.');
p = patch([PlottingTable.Distance(1:breakone);flipud(PlottingTable.Distance(1:breakone))],...
    [PlottingTable.d13C_sawtooth(1:breakone) + PlottingTable.d13C_Error(1:breakone);...
    flipud(PlottingTable.d13C_sawtooth(1:breakone) - ...
    PlottingTable.d13C_Error(1:breakone))],[0.5, 0.5, 0.5]);
q = patch([PlottingTable.Distance(breakone+1:breaktwo);flipud(PlottingTable.Distance(breakone+1:breaktwo))],...
    [PlottingTable.d13C_sawtooth(breakone+1:breaktwo) + PlottingTable.d13C_Error(breakone+1:breaktwo);...
    flipud(PlottingTable.d13C_sawtooth(breakone+1:breaktwo) - ...
    PlottingTable.d13C_Error(breakone+1:breaktwo))],[0.5, 0.5, 0.5]);
r = patch([PlottingTable.Distance(breaktwo+1:breakthree);flipud(PlottingTable.Distance(breaktwo+1:breakthree))],...
    [PlottingTable.d13C_sawtooth(breaktwo+1:breakthree) + PlottingTable.d13C_Error(breaktwo+1:breakthree);...
    flipud(PlottingTable.d13C_sawtooth(breaktwo+1:breakthree) - ...
    PlottingTable.d13C_Error(breaktwo+1:breakthree))],[0.5, 0.5, 0.5]);
s = patch([PlottingTable.Distance(breakthree+1:breakfour);flipud(PlottingTable.Distance(breakthree+1:breakfour))],...
    [PlottingTable.d13C_sawtooth(breakthree+1:breakfour) + PlottingTable.d13C_Error(breakthree+1:breakfour);...
    flipud(PlottingTable.d13C_sawtooth(breakthree+1:breakfour) - ...
    PlottingTable.d13C_Error(breakthree+1:breakfour))],[0.5, 0.5, 0.5]);
t = patch([PlottingTable.Distance(breakfour+1:end);flipud(PlottingTable.Distance(breakfour+1:end))],...
    [PlottingTable.d13C_sawtooth(breakfour+1:end) + PlottingTable.d13C_Error(breakfour+1:end);...
    flipud(PlottingTable.d13C_sawtooth(breakfour+1:end) - ...
    PlottingTable.d13C_Error(breakfour+1:end))],[0.5, 0.5, 0.5]);
set(p, 'EdgeColor','none');
set(q, 'EdgeColor','none');
set(r, 'EdgeColor','none');
set(s, 'EdgeColor','none');
set(t, 'EdgeColor','none');

alpha(0.5);

axis([0 10 -20 0]);
xlabel('WC sample order Base to top');
ylabel('\delta^{13}C VPDB');
title('Median NBS slope and sawtooth adjustment');
hold off;



%% Composite Data
StratTable = readtable('WC3 Composite Stratigraphy.xlsx');
CompositeTable = join(StratTable,PlottingTable);
CompositeTable.d18O_vpdb_published = (CompositeTable.d18O_UTM_Corrected - 30.92)./1.03092;
CompositeTable.d13C_vpdb_published = CompositeTable.d13C_sawtooth + UTM_adjust_sawtooth;

%NBS Slope, UTM Intercept same axis.
%{
figure('Position', [1,1,scrnsz(3),scrnsz(4)/2]);
yyaxis left
plot(CompositeTable.CompositeDepth(:), CompositeTable.d18O_UTM_Corrected(:),'b');
xlabel('Distance from Speleothem Top in cm','FontSize', Font);

ylabel('\delta^{18}O VPDB','FontSize', Font);
ylim([19 30]);
title('NBS slope and UTM intercept calibration');

yyaxis right
plot(CompositeTable.CompositeDepth(:), CompositeTable.d13C_UTM_Corrected(:),'k');
ylim([-15 0]);
ylabel('\delta^{13}C VPDB');
%}
%NBS Slope, Sawtooth Adjustment same axis.

figure('Position', [1,scrnsz(4)/2,scrnsz(3),scrnsz(4)/2]);
yyaxis left
plot(CompositeTable.CompositeDepth(:), CompositeTable.d18O_UTM_Corrected(:),'b');

xlabel('Distance from Speleothem Top in cm','FontSize', Font);
ylabel('\delta^{18}O VPDB','FontSize', Font);
ylim([19 30]);
title('NBS slope and Sawtooth Adjustment calibration');

yyaxis right
plot(CompositeTable.CompositeDepth(:), CompositeTable.d13C_sawtooth(:),'k');
ylim([-15 0]);
ylabel('\delta^{13}C VPDB');

%NBS Slope, Sawtooth Adjustment same axis DATE X AXIS.

figure('Position', [1,scrnsz(4)/2,scrnsz(3),scrnsz(4)/2]);
yyaxis left
plot(CompositeTable.LinDateInterp(:), CompositeTable.d18O_UTM_Corrected(:),'b');

xlabel('Date (linearly interpolated between winters and summers)','FontSize', Font);
ylabel('\delta^{18}O VPDB','FontSize', Font);
ylim([19 30]);
title('NBS slope and Sawtooth Adjustment calibration');

yyaxis right
plot(CompositeTable.LinDateInterp(:), CompositeTable.d13C_sawtooth(:),'k');
ylim([-15 0]);
ylabel('\delta^{13}C VPDB');
%{
%Plot NBS18 values (corrected, uncorrected) over time.
dates = datetime(NBS18STD.Date(:),'InputFormat','MM/dd/yyyy');
figure
plot(dates,NBS18STD.d13C_Std_Corrected(:),'o',...
   dates,NBS18STD.d13C_UTM_Corrected(:),'o',...
   dates,NBS18STD.d13C_NBS18_Corrected(:),'o',...
   dates, ones(length(dates),1)*NBS18d13Cact)
title('NBS18 values after various corrections')
xlabel('Measurement Date')
ylabel('\delta^{13}C VPDB')
legend('NBS+UTM slope+intercept','NBS+UTM slope, UTM intercept','NBS+UTM slope,NBS18 intercept')
%}
Stald13CForward

CompositeTable.d13C_CO2_Corrected = CompositeTable.d13C_sawtooth - StalRecord(:,2)
figure('Position', [1,scrnsz(4)/2,scrnsz(3),scrnsz(4)/2]);
yyaxis left
plot(CompositeTable.LinDateInterp(:), CompositeTable.d18O_UTM_Corrected(:),'b');

xlabel('Date (linearly interpolated between winters and summers)','FontSize', Font);
ylabel('\delta^{18}O VPDB','FontSize', Font);
ylim([19 30]);
title('NBS slope and Sawtooth Adjustment calibration');

yyaxis right
plot(CompositeTable.LinDateInterp(:), CompositeTable.d13C_CO2_Corrected(:),'k');
ylim([12 27]);
ylabel('\Delta^{13}C');

writetable(CompositeTable,'WC3MatlabOutput.xlsx')


figure('Position', [1,scrnsz(4)/2,scrnsz(3),scrnsz(4)/2]);
yyaxis left
plot(CompositeTable.CompositeDepth(:), CompositeTable.d18O_UTM_Corrected(:),'b');

xlabel('Date (linearly interpolated between winters and summers)','FontSize', Font);
ylabel('\delta^{18}O VPDB','FontSize', Font);
ylim([19 30]);
title('NBS slope and Sawtooth Adjustment calibration');

yyaxis right
plot(CompositeTable.CompositeDepth(:), CompositeTable.d13C_CO2_Corrected(:),'k');
ylim([12 27]);
ylabel('\Delta^{13}C');


writetable(CompositeTable,'WC3MatlabOutput.xlsx')

%}