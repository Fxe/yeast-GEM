%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% scaleBioMass
% Corrects the stoichiometry coefficients of all pseudo-rxns in an
% iterative fashion:
% 1. Switch back to original model's abundance values (Forster et al. 2003)
% 2. Improve with data from a more recent study (Lahtvee et al. 2017)
%    compatible with the current 8% lipid fraction
% 3. Rescale carbohydrate fraction (total) to have biomass add up to 1
% 4. GAM is fitted to simulate chemostat data of S. cerevisiae at low
%    growth rates (Van Hoek et al. 1988)
% 
% Function adapted from SLIMEr: https://github.com/SysBioChalmers/SLIMEr
%
% Benjamin Sanchez. Last update: 2018-09-07
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function scaleBioMass

%Load model:
initCobraToolbox
cd ..
model = loadYeastModel;
cd modelCuration

%Load data from Forster 2003:
fid = fopen('../../ComplementaryData/physiology/biomassComposition_Forster2003.tsv');
Forster2003     = textscan(fid,'%s %s %f32 %f32 %s','Delimiter','\t','HeaderLines',1);
data.mets       = Forster2003{1};
data.abundances = double(Forster2003{3});
data.MWs        = double(Forster2003{4});
data.groups     = Forster2003{5};
fclose(fid);

%Compute current composition:
sumBioMass(model,data);

%Switch to Forster 2003 data:
for i = 1:length(data.mets)
    %Find positions:
    rxnName = [data.groups{i} ' pseudoreaction'];
    rxnName = strrep(rxnName,'other','biomass');
    rxnPos  = strcmp(model.rxnNames,rxnName);
    metPos  = strcmp(model.mets,data.mets{i});
    %Extra changes in protein pseudoreaction:
    if strcmp(data.groups{i},'protein')
        oldVal = abs(model.S(metPos,rxnPos));
        metPos = abs(model.S(:,rxnPos)) == oldVal;
        if sum(metPos) ~= 2
            error('did not found tRNA(aa) pair')
        end
    end
    %Change stoichiometry:
    model.S(metPos,rxnPos) = sign(model.S(metPos,rxnPos))*data.abundances(i);
end
[~,P,~,R,~,~,~] = sumBioMass(model,data);

%Correct with data from Lahtvee 2017:
fid = fopen('../../ComplementaryData/physiology/biomassComposition_Lahtvee2017.tsv');
Lahtvee2017      = textscan(fid,'%s %s %f32 %f32 %s','Delimiter','\t','HeaderLines',1);
data2.mets       = Lahtvee2017{1};
data2.names      = Lahtvee2017{2};
data2.abundances = double(Lahtvee2017{3});
fclose(fid);
for i = 1:length(data2.mets)
    metID     = data2.mets{i};
    metName   = data2.names{i};
    abundance = data2.abundances(i);
    if strcmp(metName,'protein')      %protein fraction
        fP    = abundance/P;        %ratio to scale
        model = rescalePseudoReaction(model,'protein',fP);
        
    elseif strcmp(metName,'RNA')      %RNA fraction
        fR    = abundance/R;        %ratio to scale
        model = rescalePseudoReaction(model,'RNA',fR);
        
    else    %Some extra carbohydrates:
        modelPos = strcmp(model.mets,metID);
        compPos  = strcmp(data.mets,metID);
        rxnPos   = strcmp(model.rxnNames,'carbohydrate pseudoreaction');
        if model.S(modelPos,rxnPos) < 0
            MW = data.MWs(compPos)-18;
            model.S(modelPos,rxnPos) = -abundance/MW*1000;
        end
    end
end
[X,~,C,~,~,~,~] = sumBioMass(model,data);

%Balance out mass with carbohydrate content:
delta = X - 1;           %difference to balance
fC    = (C - delta)/C;
model = rescalePseudoReaction(model,'carbohydrate',fC);
sumBioMass(model,data);

%Fit GAM:
model = fitGAM(model);
sumBioMass(model,data);

%Finally, save model:
cd ..
saveYeastModel(model)
cd modelCuration

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function model = rescalePseudoReaction(model,metName,f)

rxnName = [metName ' pseudoreaction'];
rxnPos  = strcmp(model.rxnNames,rxnName);
for i = 1:length(model.mets)
    S_ir   = model.S(i,rxnPos);
    isProd = strcmp(model.metNames{i},[metName ' [cytoplasm]']);
    if S_ir ~= 0 && ~isProd
        model.S(i,rxnPos) = f*S_ir;
    end
end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
