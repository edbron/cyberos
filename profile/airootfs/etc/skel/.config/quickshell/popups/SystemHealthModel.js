// Formatting + health-aggregation helpers for the System Health panel.
// Pure functions only - no QML/Quickshell imports - so this can be unit
// reasoned about (and reused by the IPC state() call) without instantiating UI.

function gbFromKb(kb) {
  if (kb === null || kb === undefined) return null
  return kb / 1024 / 1024
}

function formatGb(kb, decimals) {
  var gb = gbFromKb(kb)
  if (gb === null) return "-"
  return gb.toFixed(decimals === undefined ? 1 : decimals) + " GB"
}

function formatPercent(v, decimals) {
  if (v === null || v === undefined) return "-"
  return v.toFixed(decimals === undefined ? 0 : decimals) + "%"
}

function formatMinutes(min) {
  if (min === null || min === undefined || min < 0) return null
  var h = Math.floor(min / 60)
  var m = Math.round(min % 60)
  if (h <= 0) return m + "m"
  return h + "h " + m + "m"
}

function formatHours(h) {
  if (h === null || h === undefined) return "-"
  if (h < 24) return h + " h"
  var days = Math.floor(h / 24)
  if (days < 365) return days + " d (" + h + " h)"
  var years = (days / 365).toFixed(1)
  return years + " yr (" + h + " h)"
}

function formatFreq(mhz) {
  if (mhz === null || mhz === undefined) return "-"
  if (mhz >= 1000) return (mhz / 1000).toFixed(2) + " GHz"
  return mhz + " MHz"
}

function formatTemp(c) {
  if (c === null || c === undefined) return "-"
  return c.toFixed(1) + "°C"
}

// Three-tier semantic status used for text/icon coloring throughout the panel.
// "good" | "warn" | "bad"
function batteryStatus(battery) {
  if (!battery || !battery.present) return "good"
  if (battery.healthLabel === "Poor") return "bad"
  if (battery.healthLabel === "Fair") return "warn"
  return "good"
}

function cpuStatus(cpu) {
  if (!cpu) return "good"
  if (cpu.throttled) return "bad"
  if (cpu.packageTempC !== null && cpu.packageTempC !== undefined && cpu.packageTempC >= 85) return "warn"
  return "good"
}

function memoryStatus(memory) {
  if (!memory) return "good"
  if (memory.oomKills) return "bad"
  if (memory.psi && memory.psi.fullAvg10 > 5) return "warn"
  if (memory.totalKb && memory.usedKb && (memory.usedKb / memory.totalKb) > 0.9) return "warn"
  return "good"
}

function diskStatus(disk) {
  if (!disk) return "good"
  if (disk.healthy === false) return "bad"
  if (disk.healthy === null || disk.healthy === undefined) return "warn"
  return "good"
}

function worstStatus(statuses) {
  if (statuses.indexOf("bad") >= 0) return "bad"
  if (statuses.indexOf("warn") >= 0) return "warn"
  return "good"
}

// Aggregate everything into one glance-able hero line + overall status.
function summarize(data) {
  if (!data) return { status: "good", label: "NO DATA" }

  var statuses = [
    cpuStatus(data.cpu),
    memoryStatus(data.memory),
    batteryStatus(data.battery)
  ]
  var issues = []

  if (cpuStatus(data.cpu) !== "good") issues.push("CPU")
  if (memoryStatus(data.memory) !== "good") issues.push("memory")
  if (batteryStatus(data.battery) !== "good") issues.push("battery")

  var disks = data.disks || []
  for (var i = 0; i < disks.length; i++) {
    var s = diskStatus(disks[i])
    statuses.push(s)
    if (s !== "good" && issues.indexOf("disk") < 0) issues.push("disk")
  }

  var status = worstStatus(statuses)
  var label
  if (status === "good") label = "ALL SYSTEMS NORMAL"
  else label = issues.join(", ").toUpperCase() + (issues.length > 1 ? " NEED ATTENTION" : " NEEDS ATTENTION")

  return { status: status, label: label }
}

function warningLabel(code) {
  var map = {
    available_spare: "Spare capacity low",
    temperature: "Running hot",
    degraded: "Reliability degraded",
    read_only: "Forced read-only",
    volatile_memory_backup_failed: "Backup power failure"
  }
  return map[code] || code
}

if (typeof module !== "undefined") {
  module.exports = {
    gbFromKb: gbFromKb,
    formatGb: formatGb,
    formatPercent: formatPercent,
    formatMinutes: formatMinutes,
    formatHours: formatHours,
    formatFreq: formatFreq,
    formatTemp: formatTemp,
    batteryStatus: batteryStatus,
    cpuStatus: cpuStatus,
    memoryStatus: memoryStatus,
    diskStatus: diskStatus,
    worstStatus: worstStatus,
    summarize: summarize,
    warningLabel: warningLabel
  }
}
