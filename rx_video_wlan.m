% =========================================================================
% RICEVITORE WLAN 802.11a — ADALM-Pluto SDR (VERSIONE VIDEO)
% =========================================================================
% Eseguire questo script sul PC collegato al Pluto RICEVITORE,
% DOPO aver avviato TX_WLAN_Pluto.m sull'altro PC.
%
% ADD-ONS RICHIESTI:
%   - WLAN Toolbox
%   - Communications Toolbox Support Package for Analog Devices ADALM-Pluto
%   - DSP System Toolbox 
%
% ISTRUZIONI:
%   1. Avviare prima TX_WLAN_Pluto.m sul PC trasmettitore
%   2. Copiare il valore di 'imsize' stampato dal TX nella sezione
%      CONFIGURAZIONE qui sotto
%   3. Collegare il Pluto RX via USB a questo PC
%   4. Eseguire questo script
% =========================================================================

clear;
clc;
close all;

% -------------------------------------------------------------------------
%  SEZIONE CONFIGURAZIONE — deve corrispondere al trasmettitore
% -------------------------------------------------------------------------
deviceAddress  = 'usb:0';    % Indirizzo USB del Pluto RX
channelNumber  = 13;         % Stesso canale del TX
frequencyBand  = 2.4;        % Stessa banda del TX (frequenza su cui ascoltare)
rxGain         = 35;         % Guadagno RX in dB (range: 0–73 dB per Pluto) -> Aumentare se il segnale è debole

% --- VALORE FONDAMENTALE: copiare da output del TX ---
% Leggere il valore esatto di imsize stampato dal trasmettitore
imsize = [57, 102, 3, 30];   % <-- SOSTITUIRE con i valori del TX (Il quarto numero rappresenta il numero tot di frame del video)

msduLength = 2304;           % Dimensione massima in byte del payload di ogni pacchetto MSDU (MAC Service Data Unit)
MCS_tx     = 0;              % Modulation and Coding Scheme: definisce quanto è denso il segnale (Deve corrispondere al TX)
                             % Con questi in ordine di robustezza crescente:
                             %                          - MCS = 6;     % 64-QAM  rate 2/3 — troppo sensibile
                             %                          - MCS = 4-5;   % 16-QAM  rate 3/4 — EVM tollerato ~13%
                             %                          - MCS = 2-3;   % QPSK    rate 3/4 — EVM tollerato ~18%
                             %                          - MCS = 0-1;   % BPSK    rate 1/2 — EVM tollerato ~25%, massima robustezza

% Durata della cattura in campioni (aumentare se si perdono pacchetti)
% Default: cattura per ~0.33 secondi a 30 MHz
captureMultiplier = 7;       % Moltiplicatore lunghezza waveform TX per cattura: determina per quanto tempo la radio rimane in ascolto
% -------------------------------------------------------------------------

fprintf('============================================================\n');
fprintf('  RICEVITORE WLAN 802.11a — ADALM-Pluto\n');
fprintf('============================================================\n\n');
fprintf('Configurazione: canale %d, banda %.1f GHz\n', channelNumber, frequencyBand);
fprintf('imsize atteso : [%d, %d, %d, %d]\n\n', imsize(1), imsize(2), imsize(3), imsize(4));

% =========================================================================
% STEP 1 — CONFIGURAZIONE PARAMETRI WLAN (deve rispecchiare il TX)
% =========================================================================
nonHTcfg     = wlanNonHTConfig;             % Crea un oggetto che contiene tutte le specifiche dello standard 802.11a.
nonHTcfg.MCS = MCS_tx;
chanBW       = nonHTcfg.ChannelBandwidth;   % Larghezza della banda del canale (20MHz per 802.11a)
osf          = 1;                           % Over-Sampling Factor: qui impostato a 1 (campionamento nominale a 20MHz)
sampleRate   = wlanSampleRate(nonHTcfg);    % Estrae il sample rate nominale 20 MHz 

% Numero atteso di MSDUs (calcolato dai parametri video)
totPixels = prod(imsize);                   % Moltiplica tutte e 4 le dimensioni per ottenere i byte totali del video
numMSDUs  = ceil(totPixels / msduLength);   % Calcola quanti pacchetti esatti deve aspettarsi di ricevere
fprintf('Pixel totali attesi : %d\n', totPixels);
fprintf('Numero MSDUs attesi : %d\n\n', numMSDUs);

% =========================================================================
% STEP 2 — CONFIGURAZIONE SDR RICEVITORE (Pluto)
% =========================================================================
centerFrequency = wlanChannelFrequency(channelNumber, frequencyBand);   % Converte il numero del canale nella frequenza in Hertz
fprintf('Frequenza centrale: %.3f GHz\n', centerFrequency/1e9);
fprintf('Inizializzazione SDR Pluto RX su %s...\n', deviceAddress);

% Inizializzazione della connessione USB con il Pluto SDR: imposta indirizzo, frequenza centrale, campionamento e guadagno
sdrReceiver = sdrrx('Pluto', ...
    'RadioID',            deviceAddress, ...
    'CenterFrequency',    centerFrequency, ...
    'BasebandSampleRate', sampleRate * osf, ...
    'GainSource',         'Manual', ...
    'Gain',               rxGain, ...
    'OutputDataType',     'double');

% Calcola la lunghezza di cattura come multiplo della waveform TX attesa
% La waveform TX è circa: numMSDUs * (lunghezza_pacchetto + idle_20us)
% Una stima conservativa è 10000 campioni per MSDU a 30 MHz
samplesPerMSDU   = ceil((20e-6 + 0.5e-3) * sampleRate * osf); % idle + dati
captureLen       = captureMultiplier * numMSDUs * samplesPerMSDU;
captureLen       = max(captureLen, 5e6);  % minimo 5M campioni: Calcola quanti milioni di campioni (samples) registrare, 
                                          % basandosi sul numero di pacchetti attesi più del margine, 
                                          % assicurandosi di registrare per almeno 5 milioni di campioni per non perdere dati.
sdrReceiver.SamplesPerFrame = captureLen; % Dice all'hardware quanti campioni bufferizzare prima di inviarli a MATLAB

fprintf('Lunghezza cattura: %d campioni (%.3f s)\n\n', ...
        captureLen, captureLen/(sampleRate*osf));

% =========================================================================
% STEP 3 — CONFIGURAZIONE SCOPE (spettro + costellazione)
% =========================================================================
% Grafico per vedere la densità di potenza del segnale nel dominio della frequenza
spectrumScope = spectrumAnalyzer( ...
    'SpectrumType', 'power-density', ...
    'SampleRate',   sampleRate * osf, ...
    'Title',        'Spettro segnale WLAN ricevuto', ...
    'YLabel',       'Densità spettrale di potenza', ...
    'Position',     [50 400 780 400]);

% Grafico per mostrare i simboli demodulati
refQAM = wlanReferenceSymbols('BPSK');
constellation = comm.ConstellationDiagram( ...
    'Title',                     'Simboli WLAN equalizzati', ...
    'ShowReferenceConstellation', true, ...
    'ReferenceConstellation',    refQAM, ...
    'Position',                  [850 400 440 440]);

% =========================================================================
% STEP 4 — CATTURA RF
% =========================================================================
fprintf('--- INIZIO CATTURA RF ---\n');
fprintf('In ascolto sulla frequenza %.3f GHz...\n', centerFrequency/1e9);

rxWaveform = capture(sdrReceiver, sdrReceiver.SamplesPerFrame, 'Samples');  % Pluto SDR apre il microfono radio e registra l'etere per la durata specificata 
                                                                            % Le onde elettromagnetiche grezze sono salvate in un array numerico (rxWaveform).

fprintf('Campioni acquisiti: %d\n\n', length(rxWaveform));

release(sdrReceiver);       % Libera le risorse hardware del Pluto

% Mostra spettro del segnale acquisito
spectrumScope(rxWaveform);
release(spectrumScope);

% =========================================================================
% STEP 5 — FILTRAGGIO / RATE CONVERSION (da 30 MHz a 20 MHz)
% =========================================================================
% Operazione di DSP: Digital Signal Processing
% Il Wi-Fi si aspetta dati campionati a 20 MHz.

fprintf('Filtraggio e resampling del segnale...\n');

aStop    = 40;                                                      % Attenuazione in dB desiderata della banda oscura del filtro (il filtro sopprime i rumori fuori dalla banda di interesse di almeno 40dB)
ofdmInfo = wlanNonHTOFDMInfo('NonHT-Data', nonHTcfg);               % Informazioni sui sottocanali ODFM del WiFi
SCS      = sampleRate / ofdmInfo.FFTLength;                         % Spaziatura delle sottoportanti (20MHz/lunghezza FFT (64))
txbw     = max(abs(ofdmInfo.ActiveFrequencyIndices)) * 2 * SCS;     % Transmission Bandwidth: banda utile reale del segnale 
[L, M]   = rat(1 / osf);                                            % Calcolo delle frazioni razionali per passare dal sample rate catturato ai 20MHz nominali
maxLM    = max([L M]);
R        = (sampleRate - txbw) / sampleRate;                        % Calcolo Banda di guardia
TW       = 2 * R / maxLM;                                           % Transition Width: definisce la rapidità della curva del filtro passa-basso
b        = designMultirateFIR(L, M, TW, aStop);                     % Creazione del filtro passa-basso antialiasing

firrc      = dsp.FIRRateConverter(L, M, b);                         % Applicazione del filtro: rxWaveform gira alla frequenza nativa e può essere decodificata
rxWaveform = firrc(rxWaveform);

fprintf('Segnale risampleto a %.1f MHz nominale\n\n', sampleRate/1e6);

% =========================================================================
% STEP 6 — DECODIFICA PACCHETTI
% =========================================================================
rxWaveformLen = size(rxWaveform, 1);  % Calcolo numero di campioni tot presenti nella registrazione
searchOffset  = 0;                    % Puntatore lettura: spostato in avanti a ogni pacchetto elaborato

ind       = wlanFieldIndices(nonHTcfg);     % Calcolo delle posizioni teoriche di tutti i campioni standard del preambolo 802.11a
Ns        = ind.LSIG(2) - ind.LSIG(1) + 1;  % Lunghezza in campioni di un simbolo OFDM
lstfLen   = double(ind.LSTF(2));            % Numero di campioni in L-STF
minPktLen = lstfLen * 5;                    % Soglia di sicurezza: lunghezza minima del pacchetto pari a 10 simboli OFDM

pktInd           = 1;
fineTimingOffset = [];
pktOffset        = [];
packetSeq        = [];
rxBit            = {};
msduList         = {};

evmCalculator = comm.EVM('AveragingDimensions', [1 2 3]);  % Per calcolo dell'EVM
evmCalculator.MaximumEVMOutputPort = true;

fprintf('--- INIZIO DECODIFICA PACCHETTI ---\n');

% 1. Sincronizzazione e ricerca
while (searchOffset + minPktLen) <= rxWaveformLen % ciclo while per processare i pacchetti ricevuti in ordine sparso

    % Rilevamento pacchetto
    pktOffset = wlanPacketDetect(rxWaveform, chanBW, searchOffset, 0.5);   % wlanPacketDetect analizza la forma d'onda e cerca il preambolo L-STF che indica l'inizio di un pacchetto Wi-Fi
                                                                           % 0.5: soglia di rilevamento -> se il picco di autocorrelazione supera il 50% il sistema dichiara il pacchetto L-STF trovato
    % Correzione offset del pacchetto
    pktOffset = searchOffset + pktOffset; 
    if isempty(pktOffset) || (pktOffset + double(ind.LSIG(2)) > rxWaveformLen)
        if pktInd == 1
            fprintf('\n** Nessun pacchetto rilevato nella finestra di cattura **\n');
            fprintf('   Suggerimenti:\n');
            fprintf('   - Verificare che il TX stia trasmettendo\n');
            fprintf('   - Aumentare rxGain\n');
            fprintf('   - Ridurre la distanza tra le antenne\n');
        end
        break;
    end

    % Correzione frequenza grossolana
    nonHT = rxWaveform(pktOffset + (ind.LSTF(1):ind.LSIG(2)), :);  % Estrazione campi non-HT                     
    coarseFreqOffset = wlanCoarseCFOEstimate(nonHT, chanBW);       % Calcolo e raddrizzamento dello scostamento tra gli oscillatori hardware di TX e RX
    nonHT = frequencyOffset(nonHT, sampleRate, -coarseFreqOffset);

    % Sincronizzazione temporale fine
    fineTimingOffset = wlanSymbolTimingEstimate(nonHT, chanBW);    % wlanSymbolTimingEstimate trova l'inizio esatto al singolo campione del pacchetto (usando la transizione tra L-STF e L-LTF)
    pktOffset = pktOffset + fineTimingOffset;                      % Aggiusta l'offset del pacchetto

    % Sincronizzazione temporale completata: pacchetto rilevato e sincronizzato
    if (pktOffset < 0) || ((pktOffset + minPktLen) > rxWaveformLen)
        searchOffset = pktOffset + 1.5 * lstfLen;
        continue;
    end

    fprintf('Pacchetto %d rilevato all''indice %d\n', pktInd, pktOffset + 1);

    % Estrazione preambolo e correzione CFO fine
    nonHT = rxWaveform(pktOffset + (1:7*Ns), :);  % Estrazione dei primi 7 simboli OFDM per rilevare il formato
    nonHT = frequencyOffset(nonHT, sampleRate, -coarseFreqOffset);  % Applica correzione frequenza

    lltf = nonHT(ind.LLTF(1):ind.LLTF(2), :);            % Estrazione L-LTF
    fineFreqOffset = wlanFineCFOEstimate(lltf, chanBW);  % wlanFineCFOEstimate esegue una correzione in frequenza millimetrica usando il campo L-LTF
    nonHT = frequencyOffset(nonHT, sampleRate, -fineFreqOffset);
    cfoCorrection = coarseFreqOffset + fineFreqOffset;   % CFO totale

% 2. Stima del canale (Equalizzazione)

    % Stima canale con L-LTF
    lltf = nonHT(ind.LLTF(1):ind.LLTF(2), :);            % Estrazione del campo L-LTF dal pacchetto
    demodLLTF   = wlanLLTFDemodulate(lltf, chanBW);      % Funzione di FFT sul segnale L-LTF in modo da poter analizzare la distorsione su ogni singola portante
    % Dati per invertire la distorsione sui dati reali:
    chanEstLLTF = wlanLLTFChannelEstimate(demodLLTF, chanBW); % wlanLLTFChannelEstimate usa L-LTF ideale e L-LTF ricevuta per capire com'è stato distorto il canale
    noiseVarNonHT = wlanLLTFNoiseEstimate(demodLLTF);         % Stima del rumore termico

    % Rilevamento formato
    format = wlanFormatDetect(nonHT(ind.LLTF(2) + (1:3*Ns), :), ... % Formato stimato utilizzando i 3 simboli OFDM immediatamente successivi al L-LTF
        chanEstLLTF, noiseVarNonHT, chanBW);                        % I simboli contengono l'header specifica della generazione WiFi
    fprintf('  Formato rilevato: %s\n', format);

    if ~strcmp(format, 'Non-HT')
        searchOffset = pktOffset + 1.5 * lstfLen;
        continue;
    end

% 3. Lettura dell'Header (L-SIG)

    % Decodifica L-SIG: l'header contiene informazioni sulla velocità a cui
    % viaggiano i dati successivi (MCS) e quanto è lungo il pacchetto
    [recLSIGBits, failCheck] = wlanLSIGRecover( ...         
        nonHT(ind.LSIG(1):ind.LSIG(2), :), ...
        chanEstLLTF, noiseVarNonHT, chanBW);  % wlanLSIGRecover: prende i campioni grezzi dell'L-SIG, applica l'equalizzazione (usando la stima del canale chanEstLLTF calcolata prima) e tenta di decodificare i bit. 
                                              % Esegue internamente la demodulazione BPSK e fa passare i dati attraverso un decodificatore di Viterbi per correggere eventuali errori.
                                              % Restituisce i 24 bit decodificati (recLSIGBits) e un flag booleano (failCheck)

    if failCheck
        fprintf('  L-SIG check FALLITO — pacchetto ignorato\n');
        searchOffset = pktOffset + 1.5 * lstfLen;
        continue;
    end
    fprintf('  L-SIG check OK\n');

    % Interpreta L-SIG per sapere esattamente quali campioni estrarre e come decodificarli
    % I primi 4 bit codificano il rate, i bit 5-16 codificano la lunghezza
    rateBits = recLSIGBits(1:4);
    rateCode = double(bi2de(double(rateBits)', 'left-msb'));  % bi2de converte da bit a decimale
    % Mappa codice rate → MCS (tabella IEEE 802.11-2016 Tabella 17-6)
    rateToMCS = containers.Map({13,15,5,7,9,11,1,3}, {0,1,2,3,4,5,6,7});
    if isKey(rateToMCS, rateCode)
        lsigMCS = rateToMCS(rateCode);  % Se il codice decodificato è valido salva l'MCS
    else
        lsigMCS = MCS_tx;               % fallback al MCS del trasmettitore se c'è un errore 
    end

    % Lunghezza PSDU (byte) — bit2int restituisce int, serve double per wlanNonHTConfig
    lsigLen = double(bit2int(recLSIGBits(6:17), 12, false));

    % Calcola i campioni necessari per questo pacchetto
    tempCfg  = wlanNonHTConfig('MCS', lsigMCS, 'PSDULength', lsigLen); % Configurazione temporanea con lsigLen (quanti byte ci sono) e lsigMCS (quanto densamente sono impacchettati)
    tempInd  = wlanFieldIndices(tempCfg);                              % wlanFieldIndices restituisce la posizione dell'ultimo campione utile
    rxSamples = double(tempInd.NonHTData(2));

    fprintf('  MCS=%d, PSDULength=%d byte, campioni dati=%d\n', lsigMCS, lsigLen, rxSamples);

    % Controllo per evitare errori: se l'inizio del pacchetto sommato ai
    % campioni calcolati supera la fine della registrazione il codice si ferma
    if (rxSamples + pktOffset) > length(rxWaveform)
        fprintf('  Campioni insufficienti per decodificare — fine cattura\n');
        break;
    end

    % Correzione CFO sull'intero pacchetto
    rxWaveform(pktOffset + (1:rxSamples), :) = frequencyOffset( ...             % Applico rotazione inversa di frequenza conoscendo dove finisce il pacchetto (rxSamples)
        rxWaveform(pktOffset + (1:rxSamples), :), sampleRate, -cfoCorrection);  % per stabilizzare la costellazione

    % Configurazione ricevitore Non-HT
    rxNonHTcfg             = wlanNonHTConfig;  % Generazione dell'oggetto di configurazione definitivo che contiene tutte le informazioni decodificate dall'header
    rxNonHTcfg.MCS         = lsigMCS;
    rxNonHTcfg.PSDULength  = lsigLen;
    indNonHTData = wlanFieldIndices(rxNonHTcfg, 'NonHT-Data');

% 4. Estrazione dei Dati e qualità

    % Recupero dati PSDU: restituisce il pacchetto dati corretto e i
    % simboli equalizzati (per misurare la qualità)
    [rxPSDU, eqSym] = wlanNonHTDataRecover( ...
        rxWaveform(pktOffset + (indNonHTData(1):indNonHTData(2)), :), ...  % Estrazione dell'onda dal punto in cui finisce L-SIG fino alla fine del pacchetto
        chanEstLLTF, noiseVarNonHT, rxNonHTcfg);                           % Onda elettromagnetica viene equalizzata e trasformata in bit e simboli

    % Visualizzazione costellazione ed EVM
    constellation(reshape(eqSym, [], 1));
    release(constellation);
    refSym = wlanClosestReferenceSymbol(eqSym, rxNonHTcfg);
    [evm_rms, evm_peak] = evmCalculator(refSym, eqSym);    % Calcolo dell'EVM: quanto la costellazione reale si discosta da quella ideale
    fprintf('  EVM RMS=%.2f%%, Peak=%.2f%%\n', evm_rms, evm_peak);

% 5. Livello MAC e sequenza

    % Decodifica MPDU: Prende i bit decodificati (PSDU) e controlla il livello MAC. 
    % In particolare verifica il FCS (Frame Check Sequence, un CRC). 
    % Se dice 'Success', il pacchetto è perfetto. Se fallisce, il pacchetto è corrotto.
    [cfgMACRx, msduList{pktInd}, status] = wlanMPDUDecode(rxPSDU, rxNonHTcfg);  % Calcolo del FCS: codice di controllo posizionato in coda al pacchetto, 
                                                                                          % se non coincide con quello inviato significa che il rumore ha invertito almeno un bit

    if strcmp(status, 'Success')  % Caso ideale: FCS valido
        fprintf('  MAC FCS: OK\n');
        packetSeq(pktInd) = cfgMACRx.SequenceNumber;        % Estrae il numero di sequenza del pacchetto
        msduBytes = hex2dec(cell2mat(msduList{pktInd}));    % Dati estratti sotto forma di array esadecimale e convertiti in valori decimali
        if isempty(msduBytes)
            fprintf('  MSDU vuoto — pacchetto scartato\n');
            searchOffset = pktOffset + double(indNonHTData(2));
            continue;
        end
        rxBit{pktInd} = int2bit(msduBytes, 8, false);       % Salva i byte 

    else  % Caso Pacchetto corrotto: arriva lo stesso anche se con qualche pixel del colore sbagliato
        fprintf('  MAC FCS: FALLITO (recupero dati grezzo)\n');
        bitsPerOctet         = 8;
        macHeaderBitsLength  = 24 * bitsPerOctet;  % Primi 24 byte corrispondono all'intestazione MAC
        fcsBitsLength        = 4  * bitsPerOctet;  % Ultimi 4 byte corrispondono all'FCS
        msduList{pktInd}     = rxPSDU(macHeaderBitsLength+1 : end-fcsBitsLength);  % Salvo solo quello che c'è tra l'intestazione MAC e l'FCS come payload

        % Nello standard 802.11a il campo Sequence Control si trova al byte
        % 22 e 23 ed è composto da 4 bit di Fragment Number e 12 bit di Sequence Number
        seqStart  = 23 * bitsPerOctet + 1;  % Calcolo degli indici matematici esatti per ritagliare i 12 bit dall'intestazione MAC
        seqEnd    = 25 * bitsPerOctet - 4;
        seqLen    = seqEnd - seqStart + 1;
        packetSeq(pktInd) = bit2int(rxPSDU(seqStart:seqEnd), seqLen, false); %#ok<SAGROW> % Traduzione da bit a intero
        rxBit{pktInd} = double(msduList{pktInd}); %#ok<SAGROW> % Pacchetto salvato con posizionamento
    end

    % Avanzamento offset di ricerca
    searchOffset = pktOffset + double(indNonHTData(2));

    % Incrementa indice solo se il pacchetto è stato accettato
    pktInd = pktInd + 1;

    % Uscita anticipata se abbiamo già tutti i pacchetti attesi
    if length(unique(packetSeq)) >= numMSDUs   % unique elimina i doppioni dall'array dei numeri di sequenza
        fprintf('\nTutti i pacchetti attesi ricevuti — fine decodifica\n');
        break;
    end

    % Rilevamento pacchetto duplicato → fine ciclo: siccome il tx trasmette
    % in loop se l'array di pacchetti contiene elementi doppi significa che
    % il trasmettitore sta ricominciando a inviare il video
    if length(unique(packetSeq)) < length(packetSeq)
        rxBit     = rxBit(1:length(unique(packetSeq)));
        packetSeq = packetSeq(1:length(unique(packetSeq)));
        fprintf('\nPacchetto duplicato rilevato — fine decodifica\n');
        break;
    end
end

fprintf('\nPacchetti decodificati correttamente: %d / %d\n', ...
        length(packetSeq), numMSDUs);

% Il ciclo si interrompe se si raggiunge la fine della registrazione, se si 
% ricevono tutti i pacchetti attesi, o se si nota che i pacchetti ricominciano da capo (duplicati)

% =========================================================================
% RICOSTRUZIONE DEL VIDEO (Salvataggio frame + Creazione video)
% =========================================================================
if ~(isempty(fineTimingOffset) || isempty(pktOffset))
    
    fprintf('\nRicostruzione dei dati in corso...\n');
    
    % 1. Pre-alloca l'array finale con NaN grande quanto tutti i pixel sommati di tutto il video
    decData = NaN(totPixels, 1);
    
    % 2. Inserimento posizionale basato sul MAC Sequence Number
    for i = 1:length(packetSeq)  % Per ogni pacchetto ricevuto estrae il Sequence Number
        seq = double(packetSeq(i)); 
        
        % Verifica che il pacchetto appartenga al range previsto per il video
        if seq >= 0 && seq < numMSDUs
            
            % Estrazione e conversione da bit a byte (decimali)
            bits = rxBit{i};
            bits = bits(1 : end - mod(length(bits), 8));  % Tronca la coda dell'array se la sua lunghezza non è un multiplo di 8: eventuali bit spuri / di riempimento
            bytes = bit2int(reshape(bits(:), 8, []), 8, false)'; % Converte in vettore colonna
            
            % Calcolo degli indici assoluti per il riempimento: 
            startIndex = seq * msduLength + 1; % Moltiplica il numero di sequenza per la lunghezza fissa del payload per sapere esattamente dove iniziare l'inserimento
            endIndex = min(startIndex + length(bytes) - 1, totPixels); % Calcola la fine per evitare che l'ultimo pacchetto esca dai bordi dell'array
            
            % Inserimento esatto dei dati nella "tela" grezza unidimensionale
            numBytes = endIndex - startIndex + 1;
            decData(startIndex:endIndex) = bytes(1:numBytes);  % Inserisce i byte nella posizione corretta
        end
    end

    % Reshape usa le 4 dimensioni di imsize [Altezza, Larghezza, Canali, NumeroFrame] per ricreare la struttura video. I NaN diventano 0 (pixel neri)
    receivedVideo = uint8(reshape(decData, imsize));
    
    % --- 1. SALVATAGGIO DELLE IMMAGINI UNA ALLA VOLTA ---
    cartellaFrame = 'Frame_Ricevuti';
    if ~exist(cartellaFrame, 'dir')
        mkdir(cartellaFrame);           % Crea la cartella sul disco se non esiste
    end
    
    fprintf('\nSalvataggio dei singoli frame in corso...\n');
    for k = 1:imsize(4)                 % Scorre la quarta dimensione dell'array (il numero progressivo dei frame)
        frame = receivedVideo(:,:,:,k); % Estrae tutte le righe, colonne e canali colore del frame numero k
        nomeFile = fullfile(cartellaFrame, sprintf('frame_%03d.png', k));
        imwrite(frame, nomeFile);       % Salva ogni singolo frame come immagine statica .png separata
        fprintf('Salvato: %s\n', nomeFile);
    end

    % --- 2. CREAZIONE DEL VIDEO UNICO E VISUALIZZAZIONE ---
    fprintf('\nAssemblaggio del video finale...\n');
    nomeVideo = 'video_ricevuto_finale.mp4';             % Imposta il nome e l'estensione del file .mp4
    vOut = VideoWriter(nomeVideo, 'MPEG-4');             % Specifica l'algoritmo di compressione/container 'MPEG-4'
    vOut.FrameRate = 5;                                  % Regola i FPS (in questo caso lento: 5 frame al secondo)
    open(vOut);                                          % Apre lo stream di scrittura del file video

    figure('Name', 'Video Ricevuto', 'NumberTitle', 'off');
    
    % Legge le immagini appena salvate sul disco, le aggiunge al file video e le mostra a video
    for k = 1:imsize(4)
        nomeFile = fullfile(cartellaFrame, sprintf('frame_%03d.png', k));
        imgFrame = imread(nomeFile);                     % Ricarica l'immagine salvata
        
        imshow(imgFrame);
        title(sprintf('Salvataggio e Anteprima: Frame %d / %d', k, imsize(4)));
        
        writeVideo(vOut, imgFrame);                      % Accoda il frame al file video mp4
        pause(0.1);                                      % Pausa ridotta per dare tempo all'interfaccia grafica di mostrare l'anteprima
    end
    
    close(vOut);                                         % Chiude e salva definitivamente il file video .mp4 sul computer
    close(gcf);                                          % Chiude la figura dell'anteprima usata durante il salvataggio
    fprintf('\nVideo unico salvato con successo come "%s".\n', nomeVideo);
    
    % --- 3. RIPRODUZIONE DIRETTA DEL VIDEO SALVATO ---
    fprintf('Apertura del video in MATLAB...\n');
    implay(nomeVideo);                                   % Apre il video appena salvato nel player dedicato integrato di MATLAB
    
    % Stampa una rapida statistica dei pacchetti posizionati correttamente
    pacchettiRicevuti = length(unique(packetSeq(packetSeq >= 0 & packetSeq < numMSDUs)));
    fprintf('Pacchetti validi posizionati: %d su %d (%.1f%%)\n', ...
        pacchettiRicevuti, numMSDUs, (pacchettiRicevuti/numMSDUs)*100);
        
else
    disp('Impossibile ricostruire il video: nessun pacchetto valido trovato.');
end
