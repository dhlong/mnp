function [ probChosen, d_probChosen ] = ProbitProb( theta, dataR, n, spec )

%% Construct Parameters %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% theta = [ theta; 2; 3; 4; 5; 6;];
% theta = [ theta(1:end-2); theta(end-1); theta(end); 7; 4; 1;];
params 	= ConstructParams( theta, n, spec );
base    = spec.base;

% Common price parameter ( alpha_0 )
%   alpha_0 is [ 1 x 1 ]
if ( 1 - spec.unobs ) > 0
    alpha_0     = params.alpha_0;  
end

% Consumer group specific price parameters ( alpha_r )
%   alpha_r is [ 1 x n.conGroup ]
if n.conGroup > 0
    alpha_r     = params.alpha_r;   
end

% Product characteristic parameters ( beta_1 )
%   beta_1 is [ n.maxChoice x n.prodChar ]
if ( 1 - spec.unobs ) * n.prodChar > 0
    beta_1      = params.beta_1;
end

% Consumer characteristic parameters ( beta_2 )
%   beta_2 is [ n.maxChoice x n.conChar ]
if n.conChar > 0
    beta_2      = params.beta_2;  
end

% Choleski factor of the ( differenced ) covariance matrix 
%   - the base alternative is spec.base 
%   - S is a lower-triangular matrix
%   - S is [ n.maxChoice x n.maxChoice ]
S	= params.S;

%% Compute ( Differenced ) Deterministic Utilities %%%%%%%%%%%%%%%%%%%%%%%%

V   = zeros( n.maxChoice - 1, n.con );

if ( 1 - spec.unobs ) > 0
    %   alpha_0 is [ 1 x 1 ]
    %   dataR.diff.price  is [ n.maxChoice - 1 x 1 x n.con ]
    V   = V + squeeze( alpha_0 .* dataR.diff.price );
end

if n.conGroup > 0 
    %   alpha_r is [ 1 x n.conGroup ]
    %   dataR.diff.conGroupP is [ 1 x n.conGroup x n.con ]
    temp    = bsxfun( @times, alpha_r, dataR.diff.conGroupP );   

    V       = V + squeeze( sum( temp, 2 ) );
    clear temp
end
       
if ( 1 - spec.unobs ) * n.prodChar > 0            
    %   beta_1 is [ n.maxChoice x n.prodChar ]
    %   dataR.diff.prodChar is [ (n.maxChoice - 1) x (n.maxChoice * n.prodChar) x n.con ]
    beta_1  = reshape( beta_1, [ 1 (n.maxChoice * n.prodChar) 1 ] );
    temp    = bsxfun( @times, beta_1, dataR.diff.prodChar );

    V       = V + squeeze( sum( temp, 2 ) );
    clear temp
end

if n.conChar > 0
    %   beta_2 is [ n.maxChoice x n.conChar ]
    %   dataR.diff.conChar is [ (n.maxChoice - 1) x (n.maxChoice * n.conChar) x n.con ]
    beta_2  = reshape( beta_2, [ 1 (n.maxChoice * n.conChar) 1 ] );
    temp    = bsxfun( @times, beta_2, dataR.diff.conChar );

    V       = V + squeeze( sum( temp, 2 ) );
    clear temp
end


%% Difference the Choleski Factor of the Covariance Matrix %%%%%%%%%%%%%%%%
 
S_j         = zeros( n.maxChoice - 1, n.maxChoice - 1, n.maxChoice );                
S_j_old     = S_j;

if max( abs( S_j_old(:) ) ) == 0            
    save S_j_old_save S_j_old
else
    load S_j_old_save S_j_old
end

for j = 1 : n.maxChoice
    checkPD                 = zeros( n.maxChoice, 1 ); 
    % Omega_j = Cov matrix with alternative j as base
    Omega_j                 = ( dataR.M( :, :, j, base ) * S ) * ...
                              ( dataR.M( :, :, j, base ) * S )';
    % Calculate the Choleski Factor of Omega_j and check whether the 
    %   Omega_j is positive definite                      
    [ temp, checkPD(j) ]    = chol( Omega_j, 'lower' );        
    if checkPD(j) == 0
        S_j( :, :, j )      = temp;
    else
        fprintf('\t!!! Omega_%1i is not positive definite !!!\n', j);
    end                
end
clear temp

if max( checkPD ) == 0
    % Save S_j to file if Omega_j is positive definite
    S_j_old     = S_j;        
    save S_j_old_save S_j_old
else
    % Revert to a positive definite Omega_j obatined previously
    S_j         = S_j_old;
end        

S_i     = zeros( n.maxChoice - 1, n.maxChoice - 1, n.con );
for i = 1 : n.con
    S_i( :, :, i )  = S_j( :, :, dataR.choice(i) );
end

%% Calculate Probabilities %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
probChosen  = ones( n.con, n.draw );
a           = zeros( n.con, n.draw, n.maxChoice - 1 );    
w           = zeros( n.con, n.draw, n.maxChoice - 2 );
ub          = zeros( n.con, n.draw, n.maxChoice - 1 ); 

for j = 1 : n.maxChoice - 1        
    
    if j > 1
        w( :, :, j - 1 )    = ...
            norminv( bsxfun( @times, ub( :, :, j - 1 ), ...
                             squeeze( dataR.draw.uni( j - 1, :, : ) ) ) );
    end

    a( :, :, j )    = repmat( V( j, : )', [ 1 n.draw ] );        
    for h = 1 : j - 1
        a( :, :, j )    =  bsxfun( @plus, a( :, :, j ), ...
                                   bsxfun( @times, w( :, :, h ), ...
                                           squeeze( S_i( j, h, : ) ) ) );            
    end

    a( :, :, j )    = bsxfun( @rdivide, -a( :, :, j ), ...
                              squeeze( S_i(  j,  j, : ) ) );

    ub(:,:,j) = 0.5*erfc(-a(:,:,j)/sqrt(2)); % 3x faster than normcdf                  
    probChosen      = probChosen .* ub( :, :, j );

    % Modify 0 values in 'ub' to machine epsilon to avoid division 
    %   by 0        
    ub( ub == 0 )   = eps;
    
end

if nargout == 1
    probChosen 	= mean( probChosen, 2 );  
end

%% Compute Derivatives %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if nargout > 1     
            
    % Pre-compute normpdf(a) and normpdf(w) to speed up computation
    normpdf_a                   = normpdf(a);      
    normpdf_w                   = normpdf(w);
    
    % Modify 0 values in 'ub' to machine epsilon to avoid division 
    %   by 0  
    normpdf_w( normpdf_w == 0 ) = eps;
    
    u_normpdf_a_w   = permute( dataR.draw.uni, [ 2 3 1 ] ) .* ...
                      normpdf_a( :, :, 1 : end - 1 ) ./ normpdf_w; 
    normpdf_a_ub    = reshape( normpdf_a ./ ub, ...
                               [ 1 n.con n.draw ( n.maxChoice - 1 ) ] );
                           
    % Derivatives of V wrt to beta
    if ( 1 - spec.unobs ) > 0
        d_V_beta    = permute( dataR.diff.price, [ 2 3 1 ] ); 
    else
        d_V_beta    = [];
    end
    
    if n.conGroup > 0
        d_V_beta    = [ d_V_beta; ...
                        permute( dataR.diff.conGroupP, [ 2 3 1 ] ) ];
    end
    
    if ( 1 - spec.unobs ) * n.prodChar > 0        
        d_V_beta    = [ d_V_beta; ....
                        permute( dataR.diff.prodChar, [ 2 3 1 ] ) ];        
    end
    
    if n.conChar > 0        
        d_V_beta    = [ d_V_beta; ....
                        permute( dataR.diff.conChar, [ 2 3 1 ] ) ];        
    end
    
    d_V_beta    = reshape( d_V_beta, ...
                           [ n.beta_all n.con 1 ( n.maxChoice - 1 ) ] );   
    
    % Derivatives of a wrt to beta
    d_a_beta    = zeros( n.beta_all, n.con, n.draw, n.maxChoice - 1 );    
    
    % Derivatives of w wrt to beta
    d_w_beta    = reshape( u_normpdf_a_w, ...
                           [ 1 n.con n.draw ( n.maxChoice - 2 ) ] );             
    d_w_beta    = repmat( d_w_beta, [ n.beta_all 1 1 1 ] ); 
    
    % Derivtatives of a wrt to s_i
    d_a_s_i     = zeros( n.maxChoice - 1, n.maxChoice - 1, n.con, ...
                         n.draw, n.maxChoice - 1 );
                     
    % Derivatives of w wrt to s_i              
    d_w_s_i     = reshape( u_normpdf_a_w( :, :, : ) , ...
                           [ 1 1 n.con n.draw ( n.maxChoice - 2 ) ] );

    for l = 1 : n.maxChoice - 1 
        
        % Derivatives of a wrt beta
        if l == 1            
            d_a_beta( :, :, :, l )      = ...
                        repmat( d_V_beta( :, :, :, l ), [ 1 1 n.draw 1 ] );        
        elseif l > 1        
            d_a_beta( :, :, :, l )      = ...
                        repmat( d_V_beta( :, :, :, l ), [ 1 1 n.draw 1 ] );
                    
            d_w_beta( :, :, :, l - 1 )  = d_w_beta( :, :, :, l - 1 ) .* ...
                                            d_a_beta( :, :, : , l - 1 );

            for h = 1 : l - 1            
                d_a_beta( :, :, :, l )  = d_a_beta( :, :, :, l ) + ...
                                    bsxfun( @times, d_w_beta( :, :, :, h ), ...
                                            squeeze( S_i( l, h, : ) )' );
            end            
        end
        d_a_beta( :, :, :, l )      = bsxfun( @rdivide, ...
                                              -d_a_beta( :, :, :, l ), ...
                                              squeeze( S_i( l, l, : ) )' );
    
        % Derivatives of a wrt s_i                                      
        d_a_s_i( l, l, :, :, l ) 	= -bsxfun( @rdivide, ...
                    reshape( a( :, :, l ), [ 1 1 n.con n.draw 1 ] ), ...
                    reshape( S_i( l, l, : ), [ 1 1 n.con 1 1 ] ) );
                
        for i = 1 : n.maxChoice - 1
            for j = 1 : n.maxChoice - 1
                if ( i < l ) && ( i >= j )                    
                    for h = 1 : ( l - 1 )
                        temp    = d_a_s_i( i, j, :, :, h );
                        temp    = bsxfun( @times, temp, ...
                                          d_w_s_i( :, :, :, :, h ) );
                        temp    = bsxfun( @times, temp, ...
                                          reshape( S_i( l, h, : ) ./ ...
                                                   S_i( l, l, : ), ...
                                                   [ 1 1 n.con 1 1 ] ) );
                        
                        d_a_s_i( i, j, :, :, l )    = -temp + ...
                                                d_a_s_i( i, j, :, :, l );
                    end
                elseif ( i == l ) && ( i > j )
                    d_a_s_i( i, j, :, :, l )    = -bsxfun( @rdivide, ...
                        reshape( w( :, :, j ), [ 1 1 n.con n.draw 1 ] ), ...
                        reshape( S_i( l, l, : ), [ 1 1 n.con 1 1 ] ) );
                end                
            end
        end
        
    end 
    
    % Derivatives of a wrt s
    d_a_s       = zeros( n.s + 1, n.con, n.draw, n.maxChoice - 1 );
    
    temp1        = 0;
    for j = 1 : n.maxChoice - 1
        temp2   = n.maxChoice - j;
        
        d_a_s( temp1 + 1 : temp1 + temp2, :, :, : ) = ...
                reshape( d_a_s_i( j : n.maxChoice - 1, j, :, :, : ), ...
                         [ temp2 1 n.con n.draw ( n.maxChoice - 1 ) ] );
                 
        temp1    = temp1 + temp2;         
    end
    clear temp1 temp2
    
    % Derivatives of L wrt beta
    d_L_beta    = sum( bsxfun( @times, normpdf_a_ub, d_a_beta ), 4 );
    d_L_beta    = ...
        mean( bsxfun( @times, d_L_beta, ...
                      reshape( probChosen, [ 1 n.con n.draw ] ) ), 3 );  
    
    % Derivatives of L wrt s_i
    d_L_s_i     = sum( bsxfun( @times, normpdf_a_ub, d_a_s ), 4 );
    d_L_s_i     = ...
        mean( bsxfun( @times, d_L_s_i, ...
                      reshape( probChosen, [ 1 n.con n.draw ] ) ), 3 ); 
    d_L_s_i( d_L_s_i == Inf )   = 1e+10;

    % Derivatives of s_n wrt s
    d_s_n_s     = zeros( n.s_all, n.s + 1, n.con );  
    
    % Derivatives of L wrt s
    d_L_s       = zeros( n.s_all, n.con );
    
    for i = 1 : n.con        
       A    = pinv( ...
                kron( S_i(:,:,i), eye( n.maxChoice - 1 ) ) * dataR.L + ...
                kron( eye( n.maxChoice - 1 ), S_i(:,:,i) ) * dataR.K )';
       B    = ( kron( dataR.M( :, :, dataR.choice(i), base ) * S, ...
                      dataR.M( :, :, dataR.choice(i), base ) ) * ...
                dataR.L + ...
                kron( dataR.M( :, :, dataR.choice(i), base ), ...
                      dataR.M( :, :, dataR.choice(i), base ) * S ) * ...
                dataR.K )';
       
       d_s_n_s( :, :, i )  	= B * A;
       d_L_s( :, i )        = d_s_n_s( :, :, i ) * d_L_s_i( :, i );
    end    
        
    probChosen      = mean( probChosen, 2 );
    d_probChosen    = [ d_L_beta( dataR.betaIndex, : ); 
                        d_L_s( dataR.sIndex, : ) ];
    
end













