extends RefCounted
class_name Weather
## March weather for one battle: wind (speed, direction, gusts), precipitation
## (rain / sleet / snow, with an intensity), and temperature. Rolled once from
## the March climatology, then evolved in TACTICAL time with memory — wind does
## not jump around, rain spells last hours.
##
## Everything marked SOURCED below comes from 12 Marches (2013-2024, 8,928
## hourly readings) of ERA5 reanalysis at the Svystunivka coordinates
## (Open-Meteo archive), daytime 07-17h, and from DJI's own Mavic 3 Enterprise
## manual/spec sheet. ERA5 is a 0.25-degree model, not a weather station: its
## gusts and drizzle frequency are approximate, and it smooths away heavy
## point rainfall. Everything marked JUDGMENT has no data behind it — see the
## design doc's 2026-09-21 weather entry for the full list, so they can be
## retuned in one place after watching battles.
##
## Has its OWN random stream (never the global one): drawing weather must not
## shift any seeded battle's other random draws, and the same battle seed
## gives the same weather.

static var current: Weather = null # the weather of the battle being set up or fought; null = none (tests)

enum Precip { NONE, RAIN, SLEET, SNOW }
enum Intensity { NONE, LIGHT, LIGHT_MODERATE, MODERATE, HEAVY }

# --- Wind (SOURCED) ---------------------------------------------------------
const WIND_WEIBULL_SHAPE: float = 2.44 # daytime 10 m speed: Weibull shape 2.44, scale 5.34 m/s (mean 4.7)
const WIND_WEIBULL_SCALE: float = 5.34
const WIND_HOURLY_AUTOCORR: float = 0.943 # hour-to-hour memory (measured on ln(speed)); applied to the underlying normal below
const WIND_SHEAR_EXPONENT: float = 0.14 # power law from 10 m to 100 m, measured from the same ERA5 hours (median)
const WIND_DIRECTION_SECTOR_WEIGHTS: Array[float] = [0.085, 0.114, 0.159, 0.159, 0.116, 0.130, 0.135, 0.102] # FROM N, NE, E, SE, S, SW, W, NW
const WIND_DIRECTION_DRIFT_SD_DEG_PER_SQRT_H: float = 9.0 # mean |change| 7.1 deg/h
const WIND_DIRECTION_SWING_RATE_PER_H: float = 0.013 # P(>45 deg in one hour)
const WIND_GUST_RATIO_PEAK: float = 1.9 # hourly peak gust / mean wind, median 1.93 (shown on the HUD)
# --- Wind (JUDGMENT) --------------------------------------------------------
const GUST_TURBULENCE_INTENSITY_10M: float = 0.28 # sd of instantaneous / mean speed at 10 m; ~1.9 peak over an hour
const GUST_TURBULENCE_HEIGHT_EXPONENT: float = 0.25 # turbulence intensity falls with height
const GUST_CORRELATION_S: float = 20.0

# --- Temperature (SOURCED) ---------------------------------------------------
const TEMPERATURE_MEAN_C: float = 4.0
const TEMPERATURE_SD_C: float = 5.7
const TEMPERATURE_MIN_C: float = -15.0
const TEMPERATURE_MAX_C: float = 18.0
const TEMPERATURE_DRIFT_SD_C_PER_SQRT_H: float = 0.6 # JUDGMENT: slow drift within a battle
const SNOW_BELOW_C: float = -0.5 # SOURCED split of wet hours: 23% snow, 18% mixed, 59% rain
const RAIN_ABOVE_C: float = 1.5
const DRY_SNOW_BELOW_C: float = -2.0 # JUDGMENT: colder than this the snow is dry

# --- Precipitation (SOURCED chain, JUDGMENT intensity tail) ------------------
const WET_PROBABILITY: float = 0.179 # share of daytime hours with >= 0.1 mm
const WET_SPELL_MEAN_H: float = 4.9
## Intensity is a floor of 0.1 mm/h (what counts as precipitation at all) plus a
## lognormal excess whose median is also 0.1 — so the median wet hour is 0.2 mm/h
## (SOURCED). The spread is JUDGMENT: ERA5's own is ~1.1, widened to 1.5 so
## moderate and heavy rain can happen (about 7% and 4% of events; ERA5 smooths peaks).
const INTENSITY_FLOOR_MM_H: float = 0.1
const INTENSITY_EXCESS_MEDIAN_MM_H: float = 0.1
const INTENSITY_EVENT_LOG_SD: float = 1.5
const INTENSITY_WITHIN_EVENT_LOG_SD: float = 0.5 # JUDGMENT
const INTENSITY_HOURLY_AUTOCORR: float = 0.8 # JUDGMENT
const INTENSITY_MAX_MM_H: float = 12.0

# --- Intensity classes (JUDGMENT; user's "moderate and above" reading) -------
const LIGHT_BELOW_MM_H: float = 0.5
const LIGHT_MODERATE_BELOW_MM_H: float = 1.0
const MODERATE_BELOW_MM_H: float = 3.0

# --- Drone effects ----------------------------------------------------------
const DRONE_WIND_RATING_MPS: float = 12.0 # SOURCED: DJI max wind speed resistance (spec: at takeoff and landing)
const DRONE_OPERATING_MIN_C: float = -10.0 # SOURCED: DJI operating range -10 to 40 C
const DRONE_COLD_CAPACITY_ONSET_C: float = 5.0 # SOURCED: manual — capacity significantly reduced from -10 to 5 C
const DRONE_COLD_FLIGHT_TIME_LOSS_PER_DEGREE: float = 0.015 # JUDGMENT, loosely consistent with ~50% at -18 C for Li-ion (Battery University)
const DRONE_COLD_FLIGHT_TIME_FLOOR: float = 0.5
const DRONE_COLD_HAZARD_PER_DEGREE: float = 0.10 # JUDGMENT
const DRONE_BASE_FAILURES_PER_FLIGHT_HOUR: float = 1.0 / 200.0 # JUDGMENT: no defensible published figure for small quadcopters
const DRONE_WIND_HAZARD_SCALE: float = 20.0 # JUDGMENT: multiplier 1 + 20 (v/12)^8 — about 6% per 35-minute sortie at 12 m/s, 29% at 15
const DRONE_WIND_HAZARD_EXPONENT: float = 8.0
const DRONE_RAIN_HAZARD_SCALE: float = 100.0 # JUDGMENT: below moderate, multiplier 1 + 100 * I^0.7 (6% per sortie in drizzle, 17% at 0.5 mm/h)
const DRONE_PRECIP_HAZARD_EXPONENT: float = 0.7
const DRONE_WET_RETURN_HAZARD_PER_MIN: float = 0.045 # JUDGMENT: moderate+ rain, per minute of the flight home x I^0.7 (~20% over 5 min at 1 mm/h, 60% at 8)
const DRONE_DRY_SNOW_HAZARD_FACTOR: float = 0.5 # JUDGMENT: no documented rate; the manual only groups snow with rain
const DRONE_ABORT_SHARE: float = 0.35 # JUDGMENT: share of ordinary failures that end in a forced return instead of a crash (never in moderate+ rain)
const DRONE_ALTITUDE_DECAY_PER_MM_H: float = 1.83 # JUDGMENT: fly lower to see through rain: 300 m x exp(-1.83 I) (250 at 0.1, 200 at 0.2, 120 at 0.5)
const DRONE_MIN_ALTITUDE_M: float = 60.0
const DRONE_NORMAL_ALTITUDE_M: float = GameConfig.DRONE_ALTITUDE_M
const DRONE_RESUME_BELOW_MM_H: float = 0.7 # JUDGMENT: grounded drones fly again once rain has stayed under this...
const DRONE_RESUME_AFTER_S: float = 300.0 # ...for this long

# --- Other effects (JUDGMENT) ------------------------------------------------
const GROUND_DETECTION_SCALE: Array[float] = [1.0, 0.9, 0.8, 0.6, 0.4] # by Intensity: none, light, light-moderate, moderate, heavy
const MORTAR_WIND_COUPLING: float = 0.25 # rough shell drift as a fraction of wind x flight time
const MORTAR_WIND_UNCORRECTED_SHARE: float = 0.2 # crews correct most of it (met data, observed adjustment)
const MORTAR_WIND_ALTITUDE_M: float = 300.0

var wind_speed_10m: float = 4.0 # m/s
var wind_from_deg: float = 90.0 # compass bearing the wind blows FROM (0 = north, clockwise)
var temperature_c: float = 4.0
var precip_mm_h: float = 0.0 # liquid-equivalent, 0 when dry
var enabled: bool = true
var battle_started: bool = false

var _wind_z: float = 0.0 # standard normal that wind speed is a Weibull quantile of (a Gaussian copula: AR(1) memory, real Weibull tail)
var _gust_z: float = 0.0
var _wet: bool = false
var _event_log_intensity: float = 0.0
var _log_intensity: float = 0.0
var _dry_to_wet_rate_per_h: float = (1.0 / WET_SPELL_MEAN_H) * WET_PROBABILITY / (1.0 - WET_PROBABILITY)
var rng := RandomNumberGenerator.new()


## A fresh March draw. `seed_value` < 0 means "any": draws one value from the
## global stream just to seed this weather's own.
static func roll(seed_value: int = -1) -> Weather:
	var w := Weather.new()
	w.rng.seed = seed_value if seed_value >= 0 else randi()
	w._draw_initial_state()
	return w


func _draw_initial_state() -> void:
	_wind_z = rng.randfn()
	wind_speed_10m = _speed_from_z(_wind_z)
	wind_from_deg = _draw_direction()
	temperature_c = clampf(TEMPERATURE_MEAN_C + TEMPERATURE_SD_C * rng.randfn(), TEMPERATURE_MIN_C, TEMPERATURE_MAX_C)
	_gust_z = rng.randfn()
	_wet = rng.randf() < WET_PROBABILITY
	if _wet:
		_start_event()


## The Weibull quantile at the standard-normal `z`.
static func _speed_from_z(z: float) -> float:
	var p: float = clampf(_normal_cdf(z), 1e-6, 1.0 - 1e-6)
	return maxf(0.3, WIND_WEIBULL_SCALE * pow(-log(1.0 - p), 1.0 / WIND_WEIBULL_SHAPE))


## Standard normal CDF (Abramowitz & Stegun 26.2.17, error < 8e-8).
static func _normal_cdf(z: float) -> float:
	var t: float = 1.0 / (1.0 + 0.2316419 * absf(z))
	var poly: float = t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
	var upper: float = 0.3989422804 * exp(-0.5 * z * z) * poly
	return 1.0 - upper if z >= 0.0 else upper


func _draw_direction() -> float:
	var pick: float = rng.randf()
	var sector := 0
	for i in WIND_DIRECTION_SECTOR_WEIGHTS.size():
		pick -= WIND_DIRECTION_SECTOR_WEIGHTS[i]
		if pick <= 0.0:
			sector = i
			break
	return fposmod(sector * 45.0 + rng.randf_range(-22.5, 22.5), 360.0)


func _start_event() -> void:
	_wet = true
	_event_log_intensity = log(INTENSITY_EXCESS_MEDIAN_MM_H) + INTENSITY_EVENT_LOG_SD * rng.randfn()
	_log_intensity = _event_log_intensity
	precip_mm_h = clampf(INTENSITY_FLOOR_MM_H + exp(_log_intensity), INTENSITY_FLOOR_MM_H, INTENSITY_MAX_MM_H)


## Evolves everything by `dt` tactical seconds — wind speed as an AR(1) process
## on ln(speed) (so it drifts about 19% an hour and remembers where it was),
## direction as a slow random walk with rare swings, precipitation as a
## dry/wet chain, gusts as fast noise on top.
func advance(dt: float) -> void:
	if dt <= 0.0 or not enabled:
		return
	var hours: float = dt / 3600.0

	var phi: float = pow(WIND_HOURLY_AUTOCORR, hours)
	_wind_z = phi * _wind_z + sqrt(maxf(1.0 - phi * phi, 0.0)) * rng.randfn()
	wind_speed_10m = _speed_from_z(_wind_z)

	wind_from_deg += WIND_DIRECTION_DRIFT_SD_DEG_PER_SQRT_H * sqrt(hours) * rng.randfn()
	if rng.randf() < 1.0 - exp(-WIND_DIRECTION_SWING_RATE_PER_H * hours):
		wind_from_deg += (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(45.0, 90.0)
	wind_from_deg = fposmod(wind_from_deg, 360.0)

	var gust_decay: float = exp(-dt / GUST_CORRELATION_S)
	_gust_z = _gust_z * gust_decay + sqrt(1.0 - gust_decay * gust_decay) * rng.randfn()

	temperature_c = clampf(temperature_c + TEMPERATURE_DRIFT_SD_C_PER_SQRT_H * sqrt(hours) * rng.randfn(), TEMPERATURE_MIN_C, TEMPERATURE_MAX_C)

	if _wet:
		if rng.randf() < 1.0 - exp(-hours / WET_SPELL_MEAN_H):
			_wet = false
			precip_mm_h = 0.0
		else:
			var ip: float = pow(INTENSITY_HOURLY_AUTOCORR, hours)
			_log_intensity = _event_log_intensity + ip * (_log_intensity - _event_log_intensity) + INTENSITY_WITHIN_EVENT_LOG_SD * sqrt(maxf(1.0 - ip * ip, 0.0)) * rng.randfn()
			precip_mm_h = clampf(INTENSITY_FLOOR_MM_H + exp(_log_intensity), INTENSITY_FLOOR_MM_H, INTENSITY_MAX_MM_H)
	elif rng.randf() < 1.0 - exp(-hours * _dry_to_wet_rate_per_h):
		_start_event()


# --- Wind ---------------------------------------------------------------------

## Mean wind speed (m/s) at `altitude_m` above ground.
func wind_speed_at(altitude_m: float) -> float:
	return wind_speed_10m * pow(maxf(altitude_m, 10.0) / 10.0, WIND_SHEAR_EXPONENT)


## Instantaneous / mean speed at `altitude_m` (turbulence falls with height).
func gust_multiplier(altitude_m: float) -> float:
	var ti: float = GUST_TURBULENCE_INTENSITY_10M * pow(10.0 / maxf(altitude_m, 10.0), GUST_TURBULENCE_HEIGHT_EXPONENT)
	return maxf(0.3, 1.0 + ti * _gust_z)


## The wind's velocity (m/s) in SCREEN axes — the direction it blows TOWARD,
## honoring the loaded map's own compass orientation.
func wind_velocity_mps(altitude_m: float, with_gusts: bool = true) -> Vector2:
	var speed: float = wind_speed_at(altitude_m) * (gust_multiplier(altitude_m) if with_gusts else 1.0)
	var north: Vector2 = GameConfig.CURRENT_MAP.compass_north_screen_direction
	var from_dir: Vector2 = north.rotated(deg_to_rad(wind_from_deg))
	return -from_dir * speed


## Ground speed along `dir` (a unit vector) for an aircraft with `airspeed`
## that crabs into the wind to hold its track: sqrt(airspeed^2 - crosswind^2)
## plus the along-track wind. A crosswind at or above airspeed can't be held
## against, so it barely makes headway. All in the same units (px/s or m/s).
static func ground_speed(airspeed: float, dir: Vector2, wind: Vector2) -> float:
	var along: float = wind.dot(dir)
	var cross: float = absf(wind.cross(dir))
	if cross >= airspeed:
		return maxf(along, 0.1 * airspeed)
	return maxf(sqrt(airspeed * airspeed - cross * cross) + along, 0.1 * airspeed)


# --- Precipitation -------------------------------------------------------------

func is_precipitating() -> bool:
	return _wet and precip_mm_h >= 0.1


func precip_type() -> int:
	if not is_precipitating():
		return Precip.NONE
	if temperature_c < SNOW_BELOW_C:
		return Precip.SNOW
	if temperature_c <= RAIN_ABOVE_C:
		return Precip.SLEET
	return Precip.RAIN


func intensity_class() -> int:
	if not is_precipitating():
		return Intensity.NONE
	if precip_mm_h < LIGHT_BELOW_MM_H:
		return Intensity.LIGHT
	if precip_mm_h < LIGHT_MODERATE_BELOW_MM_H:
		return Intensity.LIGHT_MODERATE
	if precip_mm_h < MODERATE_BELOW_MM_H:
		return Intensity.MODERATE
	return Intensity.HEAVY


func precip_label() -> String:
	var cls: int = intensity_class()
	if cls == Intensity.NONE:
		return ""
	var noun: String = ["", "rain", "sleet", "snow"][precip_type()]
	var adjective: String = ["", "Light", "Light-moderate", "Moderate", "Heavy"][cls]
	return "%s %s" % [adjective, noun]


func wind_label() -> String:
	return "Wind %d m/s from %s, gusts %d" % [roundi(wind_speed_10m), compass_name(wind_from_deg), roundi(wind_speed_10m * WIND_GUST_RATIO_PEAK)]


static func compass_name(deg: float) -> String:
	return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(roundf(fposmod(deg, 360.0) / 45.0)) % 8]


## One short string that changes whenever anything the HUD shows changes.
func hud_signature() -> String:
	return "%d|%s|%s|%d" % [roundi(wind_speed_10m), compass_name(wind_from_deg), precip_label(), roundi(temperature_c)]


# --- Drone effects ---------------------------------------------------------------

## True once rain/snow is heavy enough that the camera can't see the ground:
## moderate and above (the user's reading of real practice; the manual says not
## to fly in rain at all).
func drone_vision_blocked() -> bool:
	return is_precipitating() and precip_mm_h >= LIGHT_MODERATE_BELOW_MM_H


## Below that, the drone flies lower to see through the rain.
func drone_operating_altitude_m() -> float:
	if not is_precipitating():
		return DRONE_NORMAL_ALTITUDE_M
	return clampf(DRONE_NORMAL_ALTITUDE_M * exp(-DRONE_ALTITUDE_DECAY_PER_MM_H * precip_mm_h), DRONE_MIN_ALTITUDE_M, DRONE_NORMAL_ALTITUDE_M)


## Multiplies the drone's detection range: it scales with altitude (a lower
## drone sees a smaller patch), and is nothing at all once vision is blocked.
func drone_detection_scale() -> float:
	if drone_vision_blocked():
		return 0.0
	return drone_operating_altitude_m() / DRONE_NORMAL_ALTITUDE_M


## Multiplies a GROUND observer's detection range.
func ground_detection_scale() -> float:
	return GROUND_DETECTION_SCALE[intensity_class()]


## Flight time on a full battery, as a fraction of its rated value.
func drone_cold_flight_time_factor() -> float:
	return maxf(DRONE_COLD_FLIGHT_TIME_FLOOR, 1.0 - DRONE_COLD_FLIGHT_TIME_LOSS_PER_DEGREE * maxf(0.0, DRONE_COLD_CAPACITY_ONSET_C - temperature_c))


func _drone_precip_type_factor() -> float:
	return DRONE_DRY_SNOW_HAZARD_FACTOR if is_precipitating() and temperature_c < DRY_SNOW_BELOW_C else 1.0


## Per-flight-minute chance of a failure. Baseline x wind x cold x (below
## moderate) precipitation; in moderate-or-worse precipitation the drone is on
## a forced flight home, and the wet adds its own per-minute hazard instead.
func drone_hazard_per_minute(altitude_m: float) -> float:
	var base: float = DRONE_BASE_FAILURES_PER_FLIGHT_HOUR / 60.0
	var wind: float = wind_speed_at(altitude_m) * gust_multiplier(altitude_m)
	var wind_mult: float = 1.0 + DRONE_WIND_HAZARD_SCALE * pow(wind / DRONE_WIND_RATING_MPS, DRONE_WIND_HAZARD_EXPONENT)
	var cold_mult: float = 1.0 + DRONE_COLD_HAZARD_PER_DEGREE * maxf(0.0, DRONE_COLD_CAPACITY_ONSET_C - temperature_c)
	var hazard: float = base * wind_mult * cold_mult
	if is_precipitating():
		var wet_term: float = pow(precip_mm_h, DRONE_PRECIP_HAZARD_EXPONENT) * _drone_precip_type_factor()
		if drone_vision_blocked():
			hazard += DRONE_WET_RETURN_HAZARD_PER_MIN * wet_term
		else:
			hazard *= 1.0 + DRONE_RAIN_HAZARD_SCALE * wet_term
	return hazard


## What is mostly to blame for the current hazard — for the log line.
func drone_hazard_cause(altitude_m: float) -> String:
	var wind: float = wind_speed_at(altitude_m) * gust_multiplier(altitude_m)
	var wind_part: float = DRONE_WIND_HAZARD_SCALE * pow(wind / DRONE_WIND_RATING_MPS, DRONE_WIND_HAZARD_EXPONENT)
	var cold_part: float = DRONE_COLD_HAZARD_PER_DEGREE * maxf(0.0, DRONE_COLD_CAPACITY_ONSET_C - temperature_c)
	var wet_part := 0.0
	if is_precipitating():
		wet_part = DRONE_RAIN_HAZARD_SCALE * pow(precip_mm_h, DRONE_PRECIP_HAZARD_EXPONENT) * _drone_precip_type_factor()
	if wet_part >= wind_part and wet_part >= cold_part and wet_part > 0.5:
		return "the %s" % precip_label().to_lower()
	if wind_part >= cold_part and wind_part > 0.5:
		return "the wind"
	if cold_part > 0.5:
		return "the cold"
	return "a mechanical fault"


# --- Mortar ------------------------------------------------------------------------

## The uncorrected share of wind drift on a round in flight for
## `flight_time_s` seconds, in SCREEN PIXELS — an added bias on the impact
## point (crews correct most of the wind, and BattleManager fades what is left
## as fire is adjusted). Shells drift downwind.
func mortar_wind_bias_px(flight_time_s: float) -> Vector2:
	var wind_m: Vector2 = wind_velocity_mps(MORTAR_WIND_ALTITUDE_M, false)
	return wind_m * flight_time_s * MORTAR_WIND_COUPLING * MORTAR_WIND_UNCORRECTED_SHARE * GameConfig.PIXELS_PER_METER


func debug_snapshot() -> Dictionary:
	return {
		"wind_10m_mps": snappedf(wind_speed_10m, 0.1),
		"wind_300m_mps": snappedf(wind_speed_at(300.0), 0.1),
		"wind_from": compass_name(wind_from_deg),
		"wind_from_deg": roundi(wind_from_deg),
		"temperature_c": snappedf(temperature_c, 0.1),
		"precip": precip_label() if is_precipitating() else "none",
		"precip_mm_h": snappedf(precip_mm_h, 0.01) if is_precipitating() else 0.0,
		"drone_altitude_m": roundi(drone_operating_altitude_m()),
		"drone_vision_blocked": drone_vision_blocked(),
		"drone_hazard_per_min": snappedf(drone_hazard_per_minute(drone_operating_altitude_m()), 0.0001),
	}
