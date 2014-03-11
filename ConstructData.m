%% Import Data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Main Data
tempData        = importdata( spec.dataName );
dataMatrix      = tempData.data;
dataHeader      = tempData.colheaders;
clear tempData

% remove data with only 1 alternative
dataMatrix(dataMatrix(:,3) < 2, :) = [];

% for the 2160 data, station 141, 172 noone chooses the first alternative,
% which is the base alternative, thus here we simply throw them away
dataMatrix(dataMatrix(:,1) == 141, :) = [];
dataMatrix(dataMatrix(:,1) == 172, :) = [];

%% Separate data according to choice sets

conID           = dataMatrix( :, 2 );
alternative     = dataMatrix( :, 4 );
marketID        = dataMatrix( :, 1 );

uniqueID        = sort(unique(conID));
n.maxChoice     = max(alternative);
n.con           = numel(uniqueID);

choicesetcode   = zeros(size(conID));
for i = 1:n.con
    index1 = (conID == uniqueID(i));
    choiceset = false(1, n.maxChoice);
    choiceset(alternative(index1)) = true;
    choicesetcode(index1) = bin2dec(num2str(choiceset));
end

uniquecode = unique(choicesetcode);
n.choiceset = numel(uniquecode);

%% Construct the dataR structure for each choice set
for k = 1:n.choiceset
    belong = choicesetcode == uniquecode(k);
    [dataR{k}, data{k}] = ConstructDataGroup(dataMatrix(belong,:),n,spec);
end

allmarkets = sort(unique(marketID));
n.market = numel(allmarkets);
choicesetsize = zeros(size(allmarkets));
%% Identify the set of estimable parameters for each data group

% Each data group has its own set of estimable parameters, depending on the
% choice set; e.g. if the choice set does not include ethanol, then
% beta_ethanol cannot be identified using the data in the group
%
% Thus we need to construct a vector to identify which parameters (from the
% original set of parameters) are estimable in each data group (vector pick
% below)

mask.delta = zeros(n.maxChoice, n.market);
for k = 1:numel(allmarkets)
    allchoices = unique(alternative(marketID == allmarkets(k)));
    mask.delta(allchoices,k) = 1;
    choicesetsize(k) = numel(allchoices);
end
mask.delta(spec.base,:) = 0;
deltaindex = [0 cumsum(choicesetsize-1)'] + 1;

% Mask the identifiable parameters of the whole model (e.g. mark
% base-alternative $\beta$'s as not identifiable)
mask.beta_1 = ones(n.maxChoice, n.prodChar);
mask.beta_2 = ones(n.maxChoice, n.conChar);
mask.S = tril(ones(n.maxChoice, n.maxChoice));

mask.beta_2(spec.base,:) = 0;
mask.beta_1(spec.base,:) = 0;
mask.S(spec.base,:) = 0;
mask.S(:,spec.base) = 0;
mask.S(spec.scale, spec.scale) = 0;

% Count the number of estimable parameters of the full model
n.beta_1 = sum(mask.beta_1(:));
n.beta_2 = sum(mask.beta_2(:));
n.beta = n.beta_1 + n.beta_2 + 1 + n.conGroup;
n.S = sum(mask.S(:));
n.delta = deltaindex(end) - 1;
n.theta = 1+n.conGroup + n.beta_1 + n.beta_2 + n.S + n.delta;
n.maxChoice = max(dataMatrix(:,4));

% Index the estimable parameters in a running order
mask.beta_1(mask.beta_1 == 1) = 1:n.beta_1;
mask.beta_2(mask.beta_2 == 1) = 1:n.beta_2;
mask.S(mask.S == 1) = 1:n.S;

for k = 1:n.choiceset
    % Decode the choice set code to know which alternatives are missing
    missing = true(1,n.maxChoice);
    missing(dec2bin(uniquecode(k)) == '1') = false;
    
    pick.beta_1 = mask.beta_1;
    pick.beta_2 = mask.beta_2;
    pick.S = mask.S;
    
    % mark the parameters corresponding to missing alternatives as not
    % estimable
    pick.beta_1(missing,:) = 0;
    pick.beta_2(missing,:) = 0;
    pick.S(missing,:) = 0;
    pick.S(:,missing) = 0;
    
    % delete the indices of all the unestimable parameters
    pick.beta_1(pick.beta_1 == 0) = [];
    pick.beta_2(pick.beta_2 == 0) = [];
    pick.S(pick.S == 0) = [];
    
    belong = choicesetcode == uniquecode(k);
    allsubmarkets = unique(marketID(belong));
    choicesetsize = numel(unique(alternative(belong)));
    pick.delta = [];
    for j = 1:numel(allsubmarkets)
        m = find(allmarkets == allsubmarkets(j));
        pick.delta = [pick.delta deltaindex(m):deltaindex(m)+choicesetsize-2];
    end
    pick.delta = sort(pick.delta);
    
    pick.theta = (1:1+n.conGroup)'; % alpha_0, alpha_r
    % collect the indices of the rest to form vector pick.theta
    pick.theta = (1:1+n.conGroup)'; % $\alpha_0, \alpha_r$
    temp = numel(pick.theta);
    
    pick.theta = [pick.theta;pick.beta_1(:)+temp];
    temp = temp + n.beta_1;

    pick.theta = [pick.theta;pick.beta_2(:)+temp];
    temp = temp + n.beta_2;

    pick.theta = [pick.theta;pick.delta(:)+temp];
    temp = temp + n.delta;

    pick.theta = [pick.theta;pick.S(:)+temp];
    dataR{k}.pick = pick.theta;
end
