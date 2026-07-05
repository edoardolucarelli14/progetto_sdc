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
deviceAddress  = 'usb:0';   % Indirizzo USB del Pluto TX
channelNumber  = 13;        % Canale WLAN (1-13 per 2.4 GHz) -> Canale 13: 2.472GHz
frequencyBand  = 2.4;       % Banda in GHz 
txGain         = 0;         % Guadagno TX in dB (range: -89 a 0 dB)
                            % Abbassare se il segnale satura il ricevitore

fileTx         = 'peppers.png'; % Immagine da trasmettere (deve essere nel path MATLAB)
scale          = 0.2;           % Fattore di scala immagine (0.1–1.0) per ridurre il numero di byte da trasmettere
                                % Valori più alti = immagine migliore ma più pacchetti
msduLength     = 2304;          % Lunghezza MSDU in byte (max 2304 per standard 802.11)
% -------------------------------------------------------------------------

fprintf('============================================================\n');
fprintf('  TRASMETTITORE WLAN 802.11a — ADALM-Pluto\n');
fprintf('============================================================\n\n');

% --- Configurazione figure immagine ---
imFig = figure('Name','Immagine TX','NumberTitle','off');
imFig.Visible = 'off';

% =========================================================================
% STEP 1 — PREPARAZIONE IMMAGINE
% =========================================================================
fprintf('Caricamento e ridimensionamento immagine: %s\n', fileTx);

fData    = imread(fileTx);  % Lettura del file immahgine e carimento in una matrice 3D di tipo uint8
origSize = size(fData);  % Memorizza le dimensioni originali dell'immagine

% Ridimensionamento con fattore scale
scaledSize = max(floor(scale .* origSize(1:2)), 1);  % Calcola il nuovo numero di righe e colonne applicando il fattore di scala
heightIx   = min(round(((1:scaledSize(1)) - 0.5) ./ scale + 0.5), origSize(1));  % Creazione degli indici matematici per mappare 
widthIx    = min(round(((1:scaledSize(2)) - 0.5) ./ scale + 0.5), origSize(2));  % i pixel dell'immahgine originale su quella ridimensionata
fData      = fData(heightIx, widthIx, :);  % Applica il campionamento ridimensionando la matrice dell'immagine
imsize     = size(fData);   % <-- QUESTO VALORE VA COPIATO NEL RICEVITORE
txImage    = fData(:);  % Apiattisce la matrice 3D in un singolo vettore colonna 1D

fprintf('Dimensione immagine originale : %d x %d x %d\n', origSize(1), origSize(2), origSize(3));
fprintf('Dimensione immagine scalata   : %d x %d x %d\n', imsize(1),   imsize(2),   imsize(3));
fprintf('\n*** IMPORTANTE: inserire nel RX il valore imsize = [%d, %d, %d] ***\n\n', ...
        imsize(1), imsize(2), imsize(3));

% Visualizzazione immagine trasmessa
imFig.Visible = 'on';
imshow(fData);
title(sprintf('Immagine trasmessa  [%dx%d px, scala=%.1f]', imsize(2), imsize(1), scale));

% =========================================================================
% STEP 2 — FRAMMENTAZIONE IN MSDU E CREAZIONE MPDU
% =========================================================================
numMSDUs = ceil(length(txImage) / msduLength);  % Calcolo del numero di MDSU sono necessari per trasportare l'intero vettore
padZeros = msduLength - mod(length(txImage), msduLength);  % Calcolo del numero di zeri di riempimento per rendere l'ultimo pacchetto lungo esattamente 2304 byte
txData   = [txImage; zeros(padZeros, 1)];  % Aggiunta degi zeri in coda al vettore

fprintf('Numero di MSDUs da trasmettere: %d\n', numMSDUs);

data = zeros(0, 1);
for i = 0:numMSDUs-1
    frameBody = txData(i*msduLength+1 : msduLength*(i+1), :);  % Estrazione dell'i-esimo blocco dati
    cfgMAC    = wlanMACFrameConfig('FrameType', 'Data', 'SequenceNumber', i);    % Crea la struttura di configurazione per un frame MAC 802.11 di tipo 'Data', 
                                                                                 % assegnandogli un numero di sequenza progressivo (SequenceNumber)
    [psdu, lengthMPDU] = wlanMACFrame(frameBody, cfgMAC, 'OutputFormat', 'bits');  % Prende il payload grezzo (frameBody), aggiunge l'header MAC in testa 
    %                                                                                e il Frame Check Sequence (FCS/CRC) in coda per il controllo errori, 
    %                                                                               restituendo il pacchetto MAC completo sotto forma di flusso di bit 
    data = [data; psdu]; %#ok<AGROW>
end

% =========================================================================
% STEP 3 — CONFIGURAZIONE WLAN NON-HT (802.11a)
% =========================================================================
nonHTcfg                    = wlanNonHTConfig;  % Inizializza la configurazione per la modulazione OFDM standard del protocollo 802.11a
nonHTcfg.MCS                = 0;    % Modulazione BPSK con coding rate 1/2
nonHTcfg.NumTransmitAntennas = 1;   % Trasmissione a singola antenna (SISO)
nonHTcfg.PSDULength         = lengthMPDU;  % Definisce la lunghezza del payload MAC in byte (necessario per popolare correttamente il campo SIG dell'header fisico)
chanBW                      = nonHTcfg.ChannelBandwidth;

% Generazione di numeri casuali da 1 a 127 da usare come semi per lo scrambler. 
% Nel Wi-Fi, lo scrambler mescola pseudo-casualmente i bit in ingresso per evitare 
% di trasmettere lunghe sequenze di zeri o di uno che comprometterebbero la sincronizzazione OFDM del ricevitore.
scramblerInitialization = randi([1 127], numMSDUs, 1);

osf        = 1.5;  % Oversampling factor (campionamento a 30 MHz per Pluto)
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
centerFrequency = wlanChannelFrequency(channelNumber, frequencyBand);  % Converte il numero del canale nella frequenza esatta in Hz
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