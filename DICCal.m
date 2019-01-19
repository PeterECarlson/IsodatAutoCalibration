% DICCal.m
% Peter Carlson
% 6/9/2015

close all
clc
t0 = cputime;
dbstop if warning

warning('off','MATLAB:codetools:ModifiedVarnames');
warning('off','MATLAB:xlswrite:AddSheet');
warning('off','MATLAB:table:ModifiedVarnames');


SetupTable = readtable('DICCalibrationSetup.xlsx');
SetupTable = SetupTable(ismissing(SetupTable(:,1)),2:end);


%% Fixed Parameters 
%standards
STDd13Cact = -19.44; %PDB
STDmassCratio = 12.0107/(22.989769+1.00794+12.0107+3*15.9994);


PlottingTable = cell2table({});
PlotSTD =  cell2table({});

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
    STDnames = [SetupTable.Aname(i),SetupTable.Bname(i),...
        SetupTable.Cname(i),SetupTable.Dname(i),...
        SetupTable.Ename(i),SetupTable.Fname(i)];
    Blankname = char(SetupTable.Blankname(i));
    MaxStDevd18O = double(SetupTable.MaxStDevd18O(i));
    MaxStDevd13C = double(SetupTable.MaxStDevd13C(i));
    PeaksToUse = char(SetupTable.Peak(i));

    %Read input file and generate output file
    OutputAddendum = '-calibrated.xlsx'; %Avoids overwriting the input file
    TemplateExcelFile = 'DICCalTemplate.xlsx'; %do not change.
    OutputExcelFile = strrep(InputExcelFile,'.xls',OutputAddendum);


    FullTable = readtable(InputExcelFile);
    copyfile(TemplateExcelFile,OutputExcelFile);
    writetable(FullTable(:,:),OutputExcelFile,'Sheet',...
        'gasbenchCO2template.wke','Range','A1')

    FullTable(:,all(ismissing(FullTable),1)) = []; %delete empty columns
    MissingRows = ismissing(FullTable);
    FullTable = FullTable(~any(MissingRows,2),:); %del rows w/empty values

    LogTable = readtable(RunLogFile); %Future work: allow for no log file
    writetable(LogTable(:,:),OutputExcelFile,...
        'Sheet','Run Log','Range','A1');

    %Assumes first column is row numbers, second names, third/fourth notes
    LogNotes = LogTable(:,3:4);

    LogTable(:,1:4)=[];

    %Looks for a table of standard weights and volumes in the remaining cells
    StdTable = LogTable(any(~ismissing(LogTable),2),any(~ismissing(LogTable),1));
    [nonSTD, nonSTDidx] = setdiff(StdTable{:,1},STDnames);
    StdTable(nonSTDidx,:) = [];
    StdTable.ppmC = str2double(StdTable{:,2})./str2double(StdTable{:,3})...
        .*STDmassCratio.*1000;



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

    meand13C = NaN(length(Rows),1);
    stdevd13C = NaN(length(Rows),1);
    meand18O = NaN(length(Rows),1);
    stdevd18O = NaN(length(Rows),1);
    Amplitude = NaN(length(Rows),1);
    Area = NaN(length(Rows),1);

    meand13C(RowsNoBlanks) = mean(d13C,2);
    stdevd13C(RowsNoBlanks) = std(d13C,0,2);
    meand18O(RowsNoBlanks) = mean(d18O,2);
    stdevd18O(RowsNoBlanks)= std(d18O,0,2);  
    Area(RowsNoBlanks) = FullTable.Area44(SecondToLastPeakidx); 
    Amplitude(RowsNoBlanks) = FullTable.Ampl44(SecondToLastPeakidx);

    %Single peak values (no stdev here)
    meand13C(SinglePeak) = FullTable.d13C_12C(SinglePeakidx+5);
    meand18O(SinglePeak) = FullTable.d18O_16O(SinglePeakidx+5);
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
        array2table(meand13C,'VariableNames',{'d13C'}),...
        array2table(stdevd13C,'VariableNames',{'stdev_d13C'}),...
        array2table(meand18O,'VariableNames',{'d18O'}),...
        array2table(stdevd18O,'VariableNames',{'stdev_d18O'})];

    DataTable.Volume = LogNotes{:,1};
    DataTable.Notes = LogNotes{:,2};

    %% Calibrate


    %Find Standards
    Blankidx = find(strcmpi(DataTable.Identifier1,Blankname)...
        & DataTable.Peaks > 0); %only blanks with peaks

    % samples with non-failed stdev
    stdev13CBoolmat = DataTable.stdev_d13C < MaxStDevd13C;
    AmplBoolmat = DataTable.Amplitude > 1000;

    Aidx = find(strcmpi(DataTable.Identifier1,STDnames(1))...
        & stdev13CBoolmat & AmplBoolmat);

    Bidx = find(strcmpi(DataTable.Identifier1,STDnames(2))...
        & stdev13CBoolmat & AmplBoolmat);

    Cidx = find(strcmpi(DataTable.Identifier1,STDnames(3))...
        & stdev13CBoolmat & AmplBoolmat);

    Didx = find(strcmpi(DataTable.Identifier1,STDnames(4))...
        & stdev13CBoolmat & AmplBoolmat);

    Eidx = find(strcmpi(DataTable.Identifier1,STDnames(5))...
        & stdev13CBoolmat & AmplBoolmat);

    Fidx = find(strcmpi(DataTable.Identifier1,STDnames(6))...
        & stdev13CBoolmat & AmplBoolmat);

    %Only use standards that just bracket the samples.
    %e.g. If sample areas are between Stds F and C, ignore Stds A, D, E

    Sampleidx = setdiff(RowsNoBlanks,find(ismember(DataTable.Identifier1(:),STDnames)));
    MinSample = min(DataTable.Area(Sampleidx));
    MaxSample = max(DataTable.Area(Sampleidx));
    
    if isempty(Fidx) || min(DataTable.Area(Fidx)) < MinSample
        Aidx = [];
        if min(DataTable.Area(Bidx)) < MinSample
            Fidx = [];
            if min(DataTable.Area(Cidx)) < MinSample
            Bidx = [];
                if min(DataTable.Area(Didx)) < MinSample
                Cidx = [];
                end
            end
        end
    end
    if max(DataTable.Area(Didx)) > MaxSample
        Eidx = [];
        if max(DataTable.Area(Cidx)) > MaxSample
            Didx = [];
            if max(DataTable.Area(Bidx)) > MaxSample
            Cidx = [];
                if max(DataTable.Area(Fidx)) > MaxSample
                Bidx = [];
                end
            end
        end
    end        

   
    STDidx = [Aidx; Bidx; Cidx; Didx; Eidx; Fidx]; %all stds with good stdev
    STDidxAll = [...
        find(strcmpi(DataTable.Identifier1,STDnames(1)));...
        find(strcmpi(DataTable.Identifier1,STDnames(2)));...
        find(strcmpi(DataTable.Identifier1,STDnames(3)));...
        find(strcmpi(DataTable.Identifier1,STDnames(4)));...
        find(strcmpi(DataTable.Identifier1,STDnames(5)));...
        find(strcmpi(DataTable.Identifier1,STDnames(6)))];

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
        BlankArea = nanmean(DataTable.Area(Blankidx)); %mean ignoring NaN
        Blankd13C = nanmean(DataTable.d13C(Blankidx));
        Blankd18O = nanmean(DataTable.d18O(Blankidx));

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

        CorrectedError = nanstd(DataTable.d13C_Blank_Corrected(STDidx))...
            + nanstd(DataTable.d18O_Blank_Corrected(STDidx));

        UncorrectedError = nanstd(DataTable.d13C(STDidx)) +...
            nanstd(DataTable.d18O(STDidx));

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
        LinC = polyfit(DataTable.Area_Blank_Corrected(STDidx),...
            DataTable.d13C_Blank_Corrected(STDidx),1);

        LinO = polyfit(DataTable.Area_Blank_Corrected(STDidx),...
            DataTable.d18O_Blank_Corrected(STDidx),1);

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
        DriftC = polyfit(DataTable.Row(STDidx),...
            DataTable.d13C_Linearity_Corrected(STDidx),1);

        DriftO = polyfit(DataTable.Row(STDidx),...
            DataTable.d18O_Linearity_Corrected(STDidx),1);

        DataTable.d13C_Drift_Corrected = ...
            DataTable.d13C_Linearity_Corrected - ...
            (DataTable.Row-DataTable.Row(1)) .* DriftC(1);

        DataTable.d18O_Drift_Corrected = ...
            DataTable.d18O_Linearity_Corrected - ...
            (DataTable.Row-DataTable.Row(1)) .* DriftO(1);
    end

    if strcmpi(Drift,'Auto')

        CorrectedError = std(DataTable.d13C_Drift_Corrected(STDidx)) + ...
        std(DataTable.d18O_Drift_Corrected(STDidx));

        UncorrectedError = ...
            std(DataTable.d13C_Linearity_Corrected(STDidx)) + ...
            std(DataTable.d18O_Linearity_Corrected(STDidx));

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

    StdC = STDd13Cact - mean(DataTable.d13C_Drift_Corrected(STDidx));
    DataTable.d13C_Std_Corrected = DataTable.d13C_Drift_Corrected + StdC;


    Concentration = polyfit(DataTable.Area_Blank_Corrected(STDidx),...
        [DataTable.Volume(Aidx).*StdTable.ppmC(1);...
        DataTable.Volume(Bidx).*StdTable.ppmC(2);...
        DataTable.Volume(Cidx).*StdTable.ppmC(3);...
        DataTable.Volume(Didx).*StdTable.ppmC(4);...
        DataTable.Volume(Eidx).*StdTable.ppmC(5);...
        DataTable.Volume(Fidx).*StdTable.ppmC(6)], 1);

    DataTable.ppmC = (DataTable.Area_Blank_Corrected.*Concentration(1)...
        + Concentration(2))./DataTable.Volume;

    %% Calibration Data Export

    %Table of Meta-info
    Values = {Date;Analyst};
    InfoTable = table(Values);
    writetable(InfoTable,OutputExcelFile,'Sheet','Calibration','Range','F3',...
        'WriteVariableNames',false);


    %Table of Calibration Information
    CorrectionApplied = {MaxStDevd13C; PeaksUsedstr; Blank;...
        Linearity; Drift};
    CalTable = table(CorrectionApplied);
    writetable(CalTable,OutputExcelFile,'Sheet','Calibration','Range','F7',...
        'WriteVariableNames',false);

    %Standard Table
    writetable(StdTable(:,1:3),OutputExcelFile,'Sheet','Calibration',...
        'Range','E16','WriteVariableNames',false);

    %Data Table
    writetable(DataTable(:,{'Row','Identifier1', 'Volume','Amplitude',...
        'Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
        OutputExcelFile,'Sheet','Calibration','Range','B29',...
        'WriteVariableNames',false);

    %Blank Table
    if Blankidx
        writetable(DataTable(Blankidx,{'Row','Identifier1','Volume',...
            'Amplitude','Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
            OutputExcelFile,'Sheet','Calibration','Range','B131',...
            'WriteVariableNames',false);
    end

    %A Table
    if Aidx
        writetable(DataTable(Aidx,{'Row','Identifier1','Volume','Amplitude',...
            'Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
            OutputExcelFile,'Sheet','Calibration','Range','B141',...
            'WriteVariableNames',false);
    end

    %B Table
    if Bidx
        writetable(DataTable(Bidx,{'Row','Identifier1','Volume','Amplitude',...
            'Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
            OutputExcelFile,'Sheet','Calibration','Range','B147',...
            'WriteVariableNames',false);
    end

    %C Table
    if Cidx
        writetable(DataTable(Cidx,{'Row','Identifier1','Volume','Amplitude',...
            'Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
            OutputExcelFile,'Sheet','Calibration','Range','B163',...
            'WriteVariableNames',false);
    end

    %D Table
    if Didx
        writetable(DataTable(Didx,{'Row','Identifier1','Volume','Amplitude',...
            'Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
            OutputExcelFile,'Sheet','Calibration','Range','B169',...
            'WriteVariableNames',false);
    end

    %E Table
    if Eidx
        writetable(DataTable(Eidx,{'Row','Identifier1','Volume','Amplitude',...
            'Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
            OutputExcelFile,'Sheet','Calibration','Range','B175',...
            'WriteVariableNames',false);
    end

    %F Table
    if Fidx
        writetable(DataTable(Fidx,{'Row','Identifier1','Volume','Amplitude',...
            'Area','d13C','d18O','stdev_d13C','stdev_d18O'}),...
            OutputExcelFile,'Sheet','Calibration','Range','B181',...
            'WriteVariableNames',false);
    end
    %% Data Export
    % Exported Data should have no links

    d13CError = std(DataTable.d13C_Std_Corrected(STDidx));

    ExportTable = DataTable(:,{'Row','Identifier1','Volume','Notes',...
        'Area_Blank_Corrected','d13C_Std_Corrected','ppmC'});
    %    ExportTable([BlankidxAll;STDidxAll],:) = [];
    ExportTable([BlankidxAll; STDidxAll],:) = [];
    ExportTable.d13C_Error = d13CError.*ones(height(ExportTable),1);
    ExportTable.Date = repmat({Date},[height(ExportTable),1]);
    ExportTable.Analyst = repmat({Analyst},[height(ExportTable),1]);
    ExportTable.Reaction_Time = ReactionTime*ones(height(ExportTable),1);
    ExportTable.Reaction_Temp = ReactionTemp*ones(height(ExportTable),1);
    ExportTable.StdVol = repmat({DataTable.Volume(STDidx(1))},[height(ExportTable),1]);
    %Finds the closest std area for each sample
    StdMeans = [mean(DataTable.Area_Blank_Corrected(Aidx)),...
                    mean(DataTable.Area_Blank_Corrected(Bidx)),...
                    mean(DataTable.Area_Blank_Corrected(Cidx)),...
                    mean(DataTable.Area_Blank_Corrected(Didx)),...
                    mean(DataTable.Area_Blank_Corrected(Eidx)),...
                    mean(DataTable.Area_Blank_Corrected(Fidx))];
    [StdMeansSorted, Sortidx] = sort(StdMeans);
    StdNames = StdTable{Sortidx,1};
    StdMeansSorted(isnan(StdMeansSorted)) = [];
    StdEdges = [-Inf, mean([StdMeansSorted(2:end);StdMeansSorted(1:end-1)]),+Inf];
    [~,~,ClosestStdidx] = histcounts(ExportTable.Area_Blank_Corrected(:),StdEdges);
    ClosestStdidx(ClosestStdidx==0)=NaN;
    StdNaNs= isnan(ClosestStdidx);
    ClosestStd = cell(length(ClosestStdidx),1);
    ClosestStdidx(isnan(ClosestStdidx))=[];
    ClosestStd(~StdNaNs) = StdNames(ClosestStdidx);

    ExportTable.ClosestStd = ClosestStd;
    writetable(ExportTable(:,{'Identifier1','Date','Row','Identifier1',...
        'Volume'}),OutputExcelFile,'Sheet','Data Export','Range','A2',...
        'WriteVariableNames',false);
    writetable(ExportTable(:,{'Area_Blank_Corrected','d13C_Std_Corrected',...
        'd13C_Error','Analyst'}),OutputExcelFile,'Sheet','Data Export',...
        'Range','G2','WriteVariableNames',false);
    writetable(ExportTable(:,{'Reaction_Temp','Reaction_Time','Notes'}),...
        OutputExcelFile,'Sheet','Data Export','Range','L2',...
        'WriteVariableNames',false);
    %{
    %Just Peter Things
    PlottingTable = [PlottingTable; ExportTable(:,...
        {'Identifier1','Date', 'Area_Blank_Corrected','d13C_Std_Corrected','d13C_Error','ppmC','StdVol',...
        'ClosestStd', 'Notes'})];
    DataTable.i = ones(height(DataTable),1)*i;
    DataTable.stdC = ones(height(DataTable),1)*d13CError;
    PlotSTD = [PlotSTD; DataTable(STDidx,{'d13C_Std_Corrected','Area','i', 'stdC'})]; 
    %}
end

%PlotSTD



%{
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC-3','WC3');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC 3','WC3');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC 1','WC1');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC-1','WC1');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC-6','WC6');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC 6','WC6');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC Spring','WCS');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC spring','WCS');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC S','WCS');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC1-2','WC1');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC1-1','WC1');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC3-2','WC3');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC3-1','WC3');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC6-2','WC6');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC6-1','WC6');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'WC spring','WCS');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISST Indirect','ISSTI');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISST Direct','ISSTD');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISST Dir','ISSTD');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISST Ind','ISSTI');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISST IND','ISSTI');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISST DIR','ISSTD');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISCD Ind','ISCDI');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISCD Dir','ISCDD');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISCD IND','ISCDI');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISCD DIR','ISCDD');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISSR 6','ISSR6');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISSR 3','ISSR3');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISSR 4','ISSR4');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISSR 7','ISSR7');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISSR 8','ISSR8');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'ISSR 9','ISSR9');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'NBBC1','NBBC');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'NBBC2','NBBC');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'NBCT1','NBCT');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'NBCT2','NBCT');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'NBWS1','NBWS');
PlottingTable.Identifier1 = regexprep(PlottingTable.Identifier1,'NBWS2','NBWS');

WCTable = PlottingTable(~any(ismissing(PlottingTable(:,1:6)),2),:);
WCTable(strncmpi('WC ',WCTable.Identifier1(:),3),:)=[]
WCTable(~strncmpi('WC',WCTable.Identifier1(:),2),:)=[]
Name=strsplit(WCTable.Identifier1(:))

ISTable = PlottingTable(~any(ismissing(PlottingTable(:,1:6)),2),:);
ISTable(strncmpi('iso',ISTable.Identifier1(:),3),:)=[];
ISTable(strncmpi('IS ',ISTable.Identifier1(:),3),:)=[];
ISTable(strncmpi('ISDI',ISTable.Identifier1(:),3),:)=[];
ISTable(~strncmpi('IS',ISTable.Identifier1(:),2),:)=[]

NBTable = PlottingTable(~any(ismissing(PlottingTable(:,1:6)),2),:);
NBTable(strncmpi('NBS',NBTable.Identifier1(:),3),:)=[];
NBTable(strncmpi('NB ',NBTable.Identifier1(:),3),:)=[];
NBTable(strncmpi('NBDI',NBTable.Identifier1(:),3),:)=[];
NBTable(~strncmpi('NB',NBTable.Identifier1(:),2),:)=[]
%}
t1 = cputime-t0