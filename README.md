# Battery Management System FSM (Verilog)

## 📌 Overview
This project implements a **Battery Management System Fault Detection FSM** in Verilog.  
It monitors common battery pack fault conditions and transitions through four states:

- **NORM** – Normal operating conditions  
- **WARN** – Early warning (soft limit reached, but still recoverable)  
- **FAULT** – Persistent abnormal condition, protective action required  
- **SHUTDOWN** – Severe fault, latched shutdown until reset  

The design uses **debounce and persistence filters** for each input flag to avoid reacting to short spikes.

---

## ⚡ Features
- **Debounce / Persistence** per fault type:
  - Overvoltage (OV)
  - Undervoltage (UV)
  - Overtemperature (OT)
  - Undertemperature (UT)
  - Overcurrent (OC)
- **Configurable thresholds** (`DB_*`, `PERS_*`, `RCV_*`) for each category  
- **Masking** (selectively disable fault categories)  
- **Charging mode input** (`chg_en`) to treat under-temperature as critical during charging  
- **Priority resolution**:
  - SHUTDOWN > FAULT > WARN > NORM  
- **One-hot state output** (`state_1hot = {SHUTDOWN, FAULT, WARN, NORM}`)  
- **Vivado simulation testbenches** included with VCD dump

---

## 🗂️ File Structure
.
├── debounce_persist.v # Debounce/persistence counter module
├── bms_fsm.v # Main FSM with state machine logic
├── tb_bms_fsm.v # Basic testbench with VCD dump
├── tb_bms_fsm_states.v # Extended testbench printing state transitions
└── README.md # Project documentation


---

## 🏗️ How It Works
1. **Input flags** (`ov_raw`, `uv_raw`, `ot_raw`, `ut_raw`, `oc_raw`)  
   are gated by masks (`msk_*`) and fed into debounce modules.  

2. Each `debounce_persist` instance outputs:
   - `*_hi` → flag has been high for ≥ debounce cycles  
   - `*_pers` → flag has been high for ≥ persistence cycles  
   - `*_lo` → flag has been low for ≥ recovery cycles  

3. The FSM evaluates all fault categories each cycle:
   - `want_shutdown` asserted on hard faults  
   - `want_fault` asserted on persistent faults  
   - `want_warn` asserted on soft warnings  
   - `clear_ok` asserted if all categories are low long enough  

4. **State transitions** happen synchronously on the rising clock edge.

---

## ▶️ Simulation (Vivado)
1. **Create project** in Vivado and add:
   - `debounce_persist.v`
   - `bms_fsm.v`
   - Choose `tb_bms_fsm.v` or `tb_bms_fsm_states.v` as **Simulation Top**  

2. **Run Behavioral Simulation**  
   - Open the **Waveform window**  
   - Run simulation (e.g., `Run All` or for a fixed time)  

3. **Optional**: VCD dump is written (e.g., `bms_fsm_tb.vcd`)  
   You can open this with GTKWave for external viewing.

---

## 🧪 Testbench Scenarios
- **Short UV spike (< debounce)** → stays in NORM  
- **UV ≥ debounce but < persistence** → WARN, then back to NORM after recovery  
- **UV persistent ≥ persistence** → escalates to SHUTDOWN (per policy)  
- **OV ≥ debounce** → immediate SHUTDOWN  
- **OC persistent ≥ persistence** → FAULT  
- **OT ≥ debounce** → SHUTDOWN (latched)  
- **UT (discharge)** → WARN, then FAULT if persistent  
- **UT (charging)** → SHUTDOWN (critical)  
- **Masking** (e.g., `msk_uv=0`) → faults ignored  

Console output (from `tb_bms_fsm_states.v`) shows:
