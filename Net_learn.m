

function [hidneur_weights, outneur_weights, iterations] = Net_learn(X, y_d, hidneur_num, outneur_num, sec_nums, RMSE_thresh, local_thresh)

%X = matrix of MVN inputs (N x n), where N=number of learning
%samples, n = number of input variables

%y_d = (N x outneur_num) matrix of desired network outputs, expressed as class labels

%hidneur_num = number of hidden neurons
%outneur_num = number of output neurons

%sec_nums = (1 x outneur_num) vector containing the number of sectors in
%each output neuron

%local_thresh = local angular threshold for determining error

%Use the clock to set the stream of random numbers
%RandStream.setDefaultStream(RandStream('mt19937ar','seed',sum(100*clock)));
RandStream.setGlobalStream(RandStream('mt19937ar','seed',sum(100*clock)));

%Convert input values into complex numbers on the unit circle
X = exp(1i .* X);

%Determine the number of learning samples
N = size(X, 1);

%Determine the number of input variables n
n = size(X, 2);

%Generate random weights for the hidden neurons:
hidneur_weights = zeros(n+1, hidneur_num);

for hh = 1 : hidneur_num

    %real part (interval -0.5 to 0.5)
    w_re = rand(n+1, 1) - 0.5;
    %imaginary part (interval -0.5 to 0.5)
    w_im = rand(n+1, 1) - 0.5;

    %Construct a weights vector, dimensions (n+1 x 1)
    hidneur_weights(:, hh) = w_re + 1i .* w_im;

end


%Generate random weights for the output neurons:
outneur_weights = zeros(hidneur_num+1, outneur_num);

for pp = 1 : outneur_num
    
    %real part (interval -0.5 to 0.5)
    w_re = rand(hidneur_num+1, 1) - 0.5;
    %imaginary part (interval -0.5 to 0.5)
    w_im = rand(hidneur_num+1, 1) - 0.5;
    
    %Construct a weights vector, dimensions (hidneur_num+1 x 1)
    outneur_weights(:, pp) = w_re + 1i .* w_im;
end


%----

%Convert desired network output values (y_d), given as class labels, into
%desired phase values (phase_d):
phase_d = zeros(N, outneur_num);
for pp = 1 : outneur_num
    
    phase_d(:, pp) = y_d(:, pp) .* (2*pi/sec_nums(pp));
end

%Ensure that the angular range is [0, 2pi) instead of (-pi, pi)
for ii=1:N
    for pp = 1 : outneur_num
        
        if (phase_d(ii, pp) < 0)
            phase_d(ii, pp) = phase_d(ii, pp) + 2*pi;
        end
    end
end

%Determine sector size (angle), separately for each output neuron.
%sec_size is a (1 x outneur_num) vector
sec_size = 2*pi ./ sec_nums;

%Shift all desired phase values by half-sector counter-clockwise
for pp = 1 : outneur_num
    
    phase_d(:, pp) = phase_d(:, pp) + sec_size(pp)/2;
end


%Construct a matrix of desired network outputs (lying on the unit circle)
znet_d = exp(1j .* phase_d);


%append a column of 1s to X from the left, yielding a (N x n+1) matrix
%app_X
col_app(1:N) = 1;
col_app = col_app.';
app_X = [col_app X];

%Pre-compute the SVD of app_X and the pseudo-inverse of app_X. The latter
%will be used during LLS adjustment of hidden neuron weights.
%Compute the full SVD of X
[U,S,V] = svd(app_X);

%Let M = n+1
M = n+1;

%Retain only the first M columns of U, and first M rows of S
U_hat = U(:, 1:M);
S_hat = S(1:M, :); %S_hat becomes an M x M square matrix

%Construct the pseudo-inverse of S
S_hpinv = diag(1 ./ diag(S_hat));

%Construct the pseudo-inverse of X
X_pinv = V * S_hpinv * U_hat';

X_pinv = pinv(app_X);

iterations = 0;
nesovpad = 1;

min_nesovpad = N;

h = LearnStatsFig;
handles = guidata(h);

LearnFlag = 1;

min_err_all = bitmax;
min_RMSE = bitmax;

N_x_outneur_num = N * outneur_num;

while ( LearnFlag == 1)
    
    
    %Compute the output of hidden neurons for all samples
    hid_outmat = app_X * hidneur_weights;
    
    % Calculation the absolute values of the 
    % current hidden neurons weighted sums
    abs_hid_outmat = abs(hid_outmat);
    
    %Move outputs to the unit circle
    hid_outmat = hid_outmat ./ abs_hid_outmat;
    
    %Determine the network error
    [hid_errmat] = ErrBackProp(hid_outmat, outneur_weights, phase_d, znet_d, y_d, sec_size, N, hidneur_num, outneur_num, local_thresh, abs_hid_outmat);
    
    %Adjust weights of hidden neurons
    for hh = 1 : hidneur_num
        
        %hidneur_weights(:, hh) = HidNeuron_weightadj(X, hidneur_weights(:, hh), hid_errmat(:, hh), N);
        hidneur_weights(:, hh) = HidNeuron_weightadj(X, X_pinv, hidneur_weights(:, hh), hid_errmat(:, hh), N);
        
    end
   
    %Compute the output of hidden neurons for all samples
    hid_outmat = app_X * hidneur_weights;
    
    %Move outputs to the unit circle
    hid_outmat = hid_outmat ./ abs(hid_outmat);
    
    [outneur_weights, z_outneur] = OutNeuron_weightadj(hid_outmat, outneur_weights, phase_d, znet_d, y_d, sec_size, N, outneur_num, local_thresh);
    
    %Compute and display learning statistics----
    iterations = iterations + 1;
    
    %error
    %err_all = sum( (znet_d - z_outneur./abs(z_outneur))' * (znet_d - z_outneur./abs(z_outneur)) );
    
    %if (err_all < min_err_all)
    %    min_err_all = err_all;
    %end
    
    
    %Determine the number of nesovpad and angular RMSE
    current_phase = angle(z_outneur);
%    
%    for ii=1:N
%
%        for pp = 1 : outneur_num
%
%            if (current_phase(ii, pp) < 0)
%                current_phase(ii, pp) = current_phase(ii, pp) + 2*pi;
%            end
%        end
%    end
    current_phase = mod(current_phase, 2*pi);

    current_labels = zeros(N, outneur_num);
    for pp = 1 : outneur_num
        
        current_labels(:, pp) = floor(current_phase(:, pp) ./ sec_size(pp));
    end

    nesovpad = 0;
    ang_RMSE = 0;
    
    %label differences per each learning sample
    diff_labels = sum(current_labels - y_d, 2);
    
    nesovpad = sum(double(diff_labels > 0));
    
    for ii=1:N
    
        for pp = 1 : outneur_num
            
            ang_err = abs(current_phase(ii, pp) - phase_d(ii, pp));

            if (ang_err > pi)

                ang_err = 2*pi - ang_err;
            end

            ang_RMSE = ang_RMSE + ang_err^2;
        end
        
        %if (diff_labels(ii) > 0)
        %    nesovpad = nesovpad + 1;
        %end
    end
    
    
    ang_RMSE = sqrt(ang_RMSE / N_x_outneur_num);
    
    
    if (ang_RMSE < min_RMSE)
        min_RMSE = ang_RMSE;
    end
    
    %If nesovpad == 0, stop learning
    if ( (nesovpad == 0)  && (ang_RMSE < RMSE_thresh) )
        
        LearnFlag = 0;
    end
    
    if (nesovpad < min_nesovpad)
        
        min_nesovpad = nesovpad;
    end
    
    %Display the statistic in a separate figure
    set(handles.IterLabel, 'String', num2str(iterations));
    %set(handles.ErrLabel, 'String', num2str(err_all));
    %set(handles.MinErrLabel, 'String', num2str(min_err_all));
    set(handles.NesovpadLabel, 'String', num2str(nesovpad));
    set(handles.MinNesovpadLabel, 'String', num2str(min_nesovpad));
    set(handles.AngRMSELabel, 'String', num2str(ang_RMSE));
    set(handles.MinAngRMSELabel, 'String', num2str(min_RMSE));
    guidata(h, handles);
    drawnow;
    
    
    %Build a list of statistic (for all iterations)
    %verr_all(iterations) = err_all;
    %vang_RMSE(iterations) = ang_RMSE;
    %vnesovpad(iterations) = nesovpad;
    %----
end

close(h);

disp(' ');
disp(['Iteration: ', num2str(iterations)]);
%disp(['Squared norm of error ', num2str(err_all)]);
disp(['Nesovapd: ', num2str(nesovpad)]);
disp(['Ang RMSE: ', num2str(ang_RMSE)]);

disp('Learning completed!');





