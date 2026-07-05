# Prova Finale di Sistemi di Comunicazione — Trasmissione WLAN su ADALM-Pluto SDR

Questo progetto (#3) implementa un sistema di comunicazione Tx-Rx per la trasmissione e ricezione di un segnale video/immagine compresso sfruttando l'architettura **Software-Defined Radio (SDR)**. 

Il sistema utilizza terminali **Analog Devices ADALM-Pluto** e l'ambiente di sviluppo **MATLAB**, implementando lo standard **IEEE 802.11a (WLAN Non-HT)** con modulazione OFDM per garantire una trasmissione robusta su canale radio reale.

---

## 🛠️ Requisiti Software e Hardware

### Hardware Necessario
* **2x Analog Devices ADALM-Pluto SDR**: un terminale configurato come Trasmettitore (TX) e uno come Ricevitore (RX).
* **2x Antenne RF**: adatte alla frequenza dei 2.4 GHz (standard Wi-Fi).
* Cavi USB per il collegamento delle schede ai PC (è possibile eseguire TX e RX su due computer separati o su due istanze MATLAB dello stesso PC).

### Add-Ons MATLAB Richiesti
Per l'esecuzione corretta del codice è necessario installare i seguenti pacchetti aggiuntivi:
1. **WLAN Toolbox**
2. **Communications Toolbox Support Package for Analog Devices ADALM-Pluto Radio**
3. **DSP System Toolbox** (necessario per il filtraggio e il resampling multirate)

---

## 📁 Struttura della Repository

| File | Descrizione |
| :--- | :--- |
| `tx_immagine_wlan.m` | Script di trasmissione di un'immagine statica. Gestisce il ridimensionamento, la frammentazione in pacchetti MSDU/MPDU 802.11a e l'invio in loop continuo sull'hardware Pluto TX. |
| `rx_immagine_wlan.m` | Script di ricezione per immagini statiche. Esegue la cattura RF, la sincronizzazione temporale/frequenziale, l'equalizzazione OFDM e ricostruisce l'immagine ordinando i pacchetti. |
| `tx_video_wlan.m` | Script di trasmissione per stream video (`.avi`). Estrae un numero prefissato di fotogrammi, applica un downscaling spaziale, li converte in flusso di bit MAC/PHY e li trasmette via radio. |
| `rx_video_wlan.m` | Script di ricezione video. Decodifica i pacchetti nell'etere, salva i singoli fotogrammi in una cartella locale (`Frame_Ricevuti`), assembla il video finale (`.mp4`) e lo riproduce in MATLAB. |

---

## 🚀 Istruzioni per l'Esecuzione

### 1. Configurazione Preliminare
Prima di avviare gli script, verificare l'identificativo USB assegnato alle schede Pluto SDR connesse al PC aprendo la Command Window di MATLAB e digitando:

```matlab
findPlutoRadio
```

Prendere nota della stringa restituita (es. `'usb:0'`) e aggiornare la variabile `deviceAddress` all'interno della sezione **CONFIGURAZIONE** degli script TX e RX corrispondenti.

---

### 2. Trasmissione e Ricezione di un'Immagine
1. **Configurazione TX:** Aprire lo script `tx_immagine_wlan.m`. Scegliere l'immagine da trasmettere specificandola in `fileTx` (es. `'peppers.png'`) e impostare il fattore di scala `scale` (es. `0.2`).
2. **Avvio TX:** Eseguire `tx_immagine_wlan.m`. Il terminale Pluto inizierà a trasmettere la forma d'onda in loop continuo. Annotare dalla Command Window il valore stampato per le dimensioni dell'immagine
3. **Configurazione RX:** Aprire lo script `rx_immagine_wlan.m`. Nella sezione di configurazione, sostituire il vettore `imsize` con i tre valori esatti stampati dal TX alla fase precedente. Verificare che `channelNumber`, `frequencyBand` e `MCS_tx` coincidano con quelli impostati nel trasmettitore.
4. **Avvio RX:** Eseguire `rx_immagine_wlan.m`. Lo script acquisirà i campioni dall'etere per alcuni istanti, decodificherà l'header MAC ed elaborerà i payload, aprendo infine una finestra con l'immagine ricostruita.
5. **Arresto TX:** Al termine della prova, interrompere la trasmissione continua della radio eseguendo in console:
   ```matlab
   release(sdrTransmitter)
   ```

---

### 3. Trasmissione e Ricezione di un Video
1. **Preparazione Video:** Assicurarsi che il file video di input specificato nella variabile `fileTx` (es. `'shuttle.avi'`) sia presente nella cartella di lavoro di MATLAB. Regolare se desiderato il numero di fotogrammi da inviare (`numFramesToSend`).
2. **Avvio TX:** Eseguire `tx_video_wlan.m`. Lo script stamperà un vettore `imsize` a **4 dimensioni** (Altezza, Larghezza, Canali RGB, Numero di Frame). Annotare questo valore.
3. **Avvio RX:** Aprire `rx_video_wlan.m`, inserire il vettore `imsize` a 4 dimensioni appena copiato ed eseguire lo script. 
4. **Risultato Video:** Il ricevitore elaborerà i pacchetti catturati, mostrerà lo spettro e la costellazione equalizzata, salverà progressivamente i singoli frame in formato `.png` all'interno della cartella automatica `Frame_Ricevuti` ed esportando infine il video completo come `video_ricevuto_finale.mp4`.

---

## ⚙️ Parametri di Configurazione e Link Budget

All'interno dell'intestazione di ciascun file è presente una sezione **CONFIGURAZIONE** modificabile per adattare il sistema al proprio ambiente radiomobile:

* **`channelNumber` & `frequencyBand`:** Definiscono il canale Wi-Fi utilizzato per la trasmissione (es. Canale 13 = 2.472 GHz).
* **`txGain` (Guadagno TX):** Valore in dB compreso tra `-89` e `0`. Se le due antenne si trovano molto vicine sulla stessa scrivania, mantenere un valore basso per evitare la saturazione dell'amplificatore del ricevitore.
* **`rxGain` (Guadagno RX):** Valore in dB compreso tra `0` e `73`. Da aumentare nel caso in cui le schede siano distanti tra loro e l'algoritmo di rilevamento pacchetto (`wlanPacketDetect`) fallisca.
* **`MCS_tx` (Modulation and Coding Scheme):** * **`MCS = 0` (BPSK, Rate 1/2):** Massima robustezza al rumore e alle distorsioni di canale (raccomandato per i test reali in laboratorio).
  * **`MCS = 2` (QPSK, Rate 3/4):** Incrementa il throughput dati mantenendo una buona tolleranza all'EVM (~18%).
  * **`MCS = 4` (16-QAM, Rate 3/4):** Alta velocità di trasmissione ma richiede un rapporto segnale/rumore (SNR) elevato.

---

## 🔬 Architettura del Sistema e Gestione Errori

Il sistema incorpora diverse tecniche di elaborazione numerica dei segnali (DSP) e protocolli di rete per mitigare gli effetti deleteri del canale radio reale:

1. **Compensazione dell'Offset di Frequenza (CFO):** A causa delle tolleranze hardware degli oscillatori al quarzo nei due Pluto SDR, le portanti radio di TX e RX non sono mai perfettamente identiche. Gli script RX utilizzano i campi di preambolo `L-STF` e `L-LTF` per stimare l'errore di frequenza (Coarse & Fine CFO) ed applicare una derotazione di fase ai campioni prima della demodulazione OFDM.
2. **Resampling Multirate:** Poiché l'hardware Pluto opera al meglio con fattori di oversampling ($OSF > 1$, es. 30 MHz di campionamento contro i 20 MHz nominali di banda del Wi-Fi), il ricevitore implementa un convertitore di frequenza di campionamento FIR (`FIRRateConverter`) con filtro anti-aliasing per riportare il segnale esattamente a 20 MHz prima del blocco di decodifica 802.11a.
3. **Ricostruzione Resiliente:** La trasmissione via etere comporta inevitabili perdite di pacchetti o errori di bit dovuti a rumore termico e fading. Se il controllo di integrità **CRC/FCS** fallisce (restituendo status non valido), lo script non scarta l'intero pacchetto: accede direttamente all'header MAC grezzo, estrae i 12 bit del *Sequence Number* e posiziona il payload all'indice di memoria spaziale corretto. Questo approccio previene lo shift geometrico dei fotogrammi successivi, permettendo al sistema di mostrare l'immagine o il video pur in presenza di singoli pixel alterati dal rumore.

---
