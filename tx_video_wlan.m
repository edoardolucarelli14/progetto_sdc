% =========================================================================
% TRASMETTITORE WLAN 802.11a — ADALM-Pluto SDR
% =========================================================================
% Eseguire questo script sul PC collegato al Pluto TRASMETTITORE.
%
% ADD-ONS RICHIESTI:
%   - WLAN Toolbox
%   - Communications Toolbox Support Package for Analog Devices ADALM-Pluto
%
% ISTRUZIONI:
%   1. Collegare il Pluto TX via USB a questo PC
%   2. Impostare i parametri nella sezione CONFIGURAZIONE
%   3. Eseguire questo script PRIMA di avviare il ricevitore
%   4. Annotare il valore di 'imsize' stampato in console e
%      inserirlo nel codice RX_WLAN_Pluto.m prima di avviarlo
%   5. Lo script trasmette in loop continuo fino a quando non si
%      esegue: release(sdrTransmitter)  oppure si chiude MATLAB
% =========================================================================

clear;
clc;
close all;

% -------------------------------------------------------------------------
%  SEZIONE CONFIGURAZIONE — modifica questi parametri
% -------------------------------------------------------------------------
deviceAddress  = 'usb:0';   % Indirizzo USB del Pluto TX (verifica con plutoradio)
channelNumber  = 13;        % Canale WLAN (1-13 per 2.4 GHz)
frequencyBand  = 2.4;       % Banda in GHz
txGain         = 0;         % Guadagno TX in dB (range: -89 a 0 dB)
                            % Abbassare se il segnale satura il ricevitore
                            
msduLength     = 2304;      % Lunghezza MSDU in byte (max 2304 per standard 802.11)
% -------------------------------------------------------------------------

fprintf('============================================================\n');
fprintf('  TRASMETTITORE WLAN 802.11a — ADALM-Pluto\n');
fprintf('============================================================\n\n');

% --- Configurazione figure immagine ---
imFig = figure('Name','Immagine TX','NumberTitle','off');
imFig.Visible = 'off';

% =========================================================================
% STEP 1 — PREPARAZIONE VIDEO 
% =========================================================================
fileTx = 'shuttle.avi';   % <-- Inserire il nome del file video
scale  = 0.2;             % Mantenere la scala bassa (20% della risoluzione originale per ridurre il traffico dati radio)
numFramesToSend = 30;     % Numero di frame da estrarre e inviare

fprintf('Caricamento e ridimensionamento video: %s\n', fileTx);
v = VideoReader(fileTx);  % Inizializza l'oggetto VideoReader per accedere ai fotogrammi del file video

% Leggi il primo frame per capire le dimensioni di partenza
tempFrame = readFrame(v);  % Legge il primo frame come matrice 3D
origSize = size(tempFrame); % Memorizza le dimensioni originali 

% Calcola indici di ridimensionamento
scaledSize = max(floor(scale .* origSize(1:2)), 1);  % Calcolo delle nuove dimensioni spaziali ridotte
heightIx   = min(round(((1:scaledSize(1)) - 0.5) ./ scale + 0.5), origSize(1)); % Vettore degli indici delle righe da campionare
widthIx    = min(round(((1:scaledSize(2)) - 0.5) ./ scale + 0.5), origSize(2)); % Vettore degli indici delle colonne da campionare

% Pre-alloca la matrice 4D: [Altezza, Larghezza, CanaliRGB, NumFrames]
frames = zeros(length(heightIx), length(widthIx), 3, numFramesToSend, 'uint8');

% Estrai e scala i frame dal video
v.CurrentTime = 0; % Reset all'inizio del video
for k = 1:numFramesToSend  
    if hasFrame(v)  % Verifica che il file video contenga ancora fotogrammi da leggere
        f = readFrame(v);
        frames(:,:,:,k) = f(heightIx, widthIx, :); % Salva il frame scalato
    end
end

% Il nuovo imsize ora ha 4 dimensioni!
imsize  = size(frames); 
txImage = frames(:); % Appiattisce tutto il video in un singolo vettore 1D

fprintf('\n** IMPORTANTE: inserire nel RX il valore imsize = [%d, %d, %d, %d] **\n\n', ...
        imsize(1), imsize(2), imsize(3), imsize(4));

% =========================================================================
% STEP 2 — FRAMMENTAZIONE IN MSDU E CREAZIONE MPDU
% =========================================================================
numMSDUs = ceil(length(txImage) / msduLength);  % Calcolo del numero di MDSU necessari pern trasportare tutto il video
padZeros = msduLength - mod(length(txImage), msduLength);  % Calcolo del numeri di zeri per il padding
txData   = [txImage; zeros(padZeros, 1)]; % Aggiunta del padding in cosa al vettore dati

fprintf('Numero di MSDUs da trasmettere: %d\n', numMSDUs);

data = zeros(0, 1);
for i = 0:numMSDUs-1
    frameBody = txData(i*msduLength+1 : msduLength*(i+1), :);
    cfgMAC    = wlanMACFrameConfig('FrameType', 'Data', 'SequenceNumber', i);  % Configurazione header pacchetto MAC e numero di sequenza
    [psdu, lengthMPDU] = wlanMACFrame(frameBody, cfgMAC, 'OutputFormat', 'bits'); % Generazione del pacchetto MAC completo con header e controllo errori CRC/FCS
    data = [data; psdu]; % Accoda i bit prodotti alla sequenza di trasmissione globale
end

% =========================================================================
% STEP 3 — CONFIGURAZIONE WLAN NON-HT (802.11a)
% =========================================================================
nonHTcfg                    = wlanNonHTConfig; % Inizializza la configurazione per la modulazione OFDM standard del protocollo 802.11a
nonHTcfg.MCS                = 0;    % Modulazione BPSK con coding rate 1/2
nonHTcfg.NumTransmitAntennas = 1;   % Trasmissione a singola antenna (SISO)
nonHTcfg.PSDULength         = lengthMPDU; % Definisce la lunghezza del payload MAC in byte (necessario per popolare correttamente il campo SIG dell'header fisico)
chanBW                      = nonHTcfg.ChannelBandwidth; % Larghezza di banda nominale del canale (20MHz)

% Generazione di numeri casuali da 1 a 127 da usare come semi per lo scrambler. 
% Nel Wi-Fi, lo scrambler mescola pseudo-casualmente i bit in ingresso per evitare 
% di trasmettere lunghe sequenze di zeri o di uno che comprometterebbero la sincronizzazione OFDM del ricevitore.
scramblerInitialization = randi([1 127], numMSDUs, 1);

osf        = 1;  % Oversampling factor 
sampleRate = wlanSampleRate(nonHTcfg);  % 20 MHz nominale

fprintf('Sample rate nominale  : %.1f MHz\n', sampleRate/1e6);
fprintf('Sample rate effettivo : %.1f MHz (osf=%.1f)\n', sampleRate*osf/1e6, osf);

% =========================================================================
% STEP 4 — GENERAZIONE WAVEFORM BASEBAND
% =========================================================================
fprintf('\nGenerazione waveform WLAN...\n');

txWaveform = wlanWaveformGenerator(data, nonHTcfg, ...  % Prende la sequenza grezza di bit (data) e la trasforma nella vera forma d'onda digitale I/Q complessa nel tempo
    'NumPackets',              numMSDUs, ...
    'IdleTime',                20e-6, ...               % Pausa di silenzio radio di 20 microsecondi tra un pacchetto e l'altro per permettere a RX di elaborare i pacchetti separatamente
    'ScramblerInitialization', scramblerInitialization, ...
    'OversamplingFactor',      osf);

fprintf('Lunghezza waveform generata: %d campioni (%.3f ms)\n', ...
        length(txWaveform), length(txWaveform)/(sampleRate*osf)*1e3);

% =========================================================================
% STEP 5 — CONFIGURAZIONE SDR TRASMETTITORE (Pluto)
% =========================================================================
centerFrequency = wlanChannelFrequency(channelNumber, frequencyBand); % Converte il numero del canale nella frequenza esatta in Hz
fprintf('\nFrequenza centrale: %.3f GHz (canale %d, banda %.1f GHz)\n', ...
        centerFrequency/1e9, channelNumber, frequencyBand);

fprintf('Inizializzazione SDR Pluto TX su %s...\n', deviceAddress);

% Controllo dell'hardware fisico del Pluto SDR
sdrTransmitter = sdrtx('Pluto', ...
    'RadioID',           deviceAddress, ...
    'CenterFrequency',   centerFrequency, ...
    'BasebandSampleRate', sampleRate * osf, ...
    'Gain',              txGain);

% =========================================================================
% STEP 6 — NORMALIZZAZIONE E TRASMISSIONE CONTINUA
% =========================================================================
powerScaleFactor = 0.8;  % Riduce il picco a 0.8 (cioè all'80% della scala dinamica del DAC). 
%                          Questo margine del 20% è fondamentale nell'OFDM per evitare il clipping digitale 
%                          (saturazione hardware interna ai convertitori numerico-analogici) causato dall'alto rapporto di picco/potenza media (PAPR) dell'OFDM.
txWaveform = txWaveform / max(abs(txWaveform)) * powerScaleFactor; % Normalizza il segnale in modo che il picco massimo di modulo sia 1

fprintf('\n--- INIZIO TRASMISSIONE CONTINUA ---\n');
fprintf('Il Pluto TX sta trasmettendo in loop sul canale %d (%.3f GHz)\n', ...
        channelNumber, centerFrequency/1e9);
fprintf('Avviare ora il ricevitore sull''altro PC.\n');
fprintf('Per fermare la trasmissione eseguire: release(sdrTransmitter)\n\n');

transmitRepeat(sdrTransmitter, txWaveform);  % Carica l'intera forma d'onda generata nella memoria RAM interna del dispositivo ADALM-Pluto 
%                                              e avvia una trasmissione hardware circolare e continua in loop.

% =========================================================================
% NOTE FINALI
% =========================================================================
% Per fermare manualmente la trasmissione:
%   >> release(sdrTransmitter)
%
% Parametri da comunicare al ricevitore:
fprintf('=== PARAMETRI DA INSERIRE NEL RICEVITORE ===\n');
fprintf('  imsize        = [%d, %d, %d]\n', imsize(1), imsize(2), imsize(3));
fprintf('  channelNumber = %d\n', channelNumber);
fprintf('  frequencyBand = %.1f\n', frequencyBand);
fprintf('  MCS           = %d\n', nonHTcfg.MCS);
fprintf('  msduLength    = %d\n', msduLength);
fprintf('  numMSDUs      = %d\n', numMSDUs);
fprintf('============================================\n');