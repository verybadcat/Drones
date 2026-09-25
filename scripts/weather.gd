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
enum Intensity { NONE, DRIZZLE, LIGHT, MODERATE, HEAVY }

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

# --- Intensity classes -------------------------------------------------------
## The standard rate scale (American Meteorological Society Glossary; the UK Met Office's
## Fact Sheet 3 agrees on light and differs on the upper bounds, 10 and 10-50 mm/h):
## light rain under 2.5 mm/h, moderate 2.5 to 7.6, heavy above 7.6 (violent, over 50 mm/h,
## is beyond anything this model produces: INTENSITY_MAX_MM_H). Drizzle is not a rate class
## in those sources — the Met Office is explicit that the difference from rain "is purely
## one of drop size rather than intensity" — and drop size is not modelled here, so, by the
## user's decision, the lightest rain, up to and INCLUDING 0.5 mm/h, is called drizzle.
## The classes only NAME and LABEL the rain (and pick its sound): what it does to drones and
## observers depends on the rate itself, by the constants below, not on the class.
const DRIZZLE_UP_TO_MM_H: float = 0.5
const LIGHT_BELOW_MM_H: float = 2.5
const MODERATE_BELOW_MM_H: float = 7.6
## Hysteresis on the class: the intensity is a random walk (see advance), so near a
## boundary it jitters across it many times. A class only changes once the intensity
## is this fraction PAST the boundary, so a jitter that stays inside the band changes
## nothing while a real change of strength still does. JUDGMENT.
const INTENSITY_CLASS_HYSTERESIS: float = 0.1
## The intensity number the HUD shows holds its value until the true intensity is
## further from it than this (the larger of DISPLAY_HOLD_MIN_MM_H and this fraction of
## the shown value): a slightly untrue but steady reading, rather than digits that
## shimmer as the random walk crosses a rounding edge. JUDGMENT.
const DISPLAY_HOLD_FRACTION: float = 0.1
const DISPLAY_HOLD_MIN_MM_H: float = 0.07

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
## Below DRONE_BLIND_FROM_MM_H the failure chance is multiplied by 1 + 30 * I: water on a
## non-waterproof airframe, so the risk goes with how much falls on it, in proportion to the
## rate. About 1% per 35-minute sortie at 0.1 mm/h, 5% at 0.5, 9% at 1, 20% at 2.4 (the
## baseline alone is 0.3%). JUDGMENT: no published figure was found; the anchor is that a
## sortie just short of the grounding rate is a real gamble. (Before the standard classes
## were adopted this was 1 + 100 * I^0.7 — 6% at 0.1, 17% at 0.5, 25% at 1, 42% at 2.4 —
## which made even trace drizzle a serious risk.)
const DRONE_RAIN_HAZARD_SCALE: float = 30.0
const DRONE_PRECIP_HAZARD_EXPONENT: float = 1.0
const DRONE_RETURN_HAZARD_EXPONENT: float = 0.7 # the blind flight home, below
const DRONE_WET_RETURN_HAZARD_PER_MIN: float = 0.045 # JUDGMENT: at or above DRONE_BLIND_FROM_MM_H, per minute of the flight home x I^0.7 (~35% over 5 min at 2.5 mm/h, 60% at 8)
const DRONE_DRY_SNOW_HAZARD_FACTOR: float = 0.5 # JUDGMENT: no documented rate; the manual only groups snow with rain
const DRONE_ABORT_SHARE: float = 0.35 # JUDGMENT: share of ordinary failures that end in a forced return instead of a crash (never once blind)
## The drone flies lower to see through rain, and sees less: 300 m x exp(-k I), reaching the
## minimum altitude (and a fifth of its normal detection range) exactly where the camera is
## blinded, so the loss is spread over the whole light-rain range instead of piled into its
## first millimetre: about 280 m at 0.1 mm/h, 220 at 0.5, 160 at 1, 80 at 2, 60 at 2.5. JUDGMENT.
const DRONE_ALTITUDE_DECAY_PER_MM_H: float = 0.644 # = ln(300 / 60) / DRONE_BLIND_FROM_MM_H
const DRONE_MIN_ALTITUDE_M: float = 60.0
const DRONE_NORMAL_ALTITUDE_M: float = GameConfig.DRONE_ALTITUDE_M
## Rain this heavy blinds the camera at once (lens and dome swamped; the manual says not to
## fly in rain at all): whatever is searching is recalled and nothing launches. It is the
## bottom of the standard MODERATE rain class — "people don't fly in even moderate rain", the
## user's own reading of practice — but a rate, not a class: retune it here. JUDGMENT.
const DRONE_BLIND_FROM_MM_H: float = 2.5
const DRONE_RESUME_BELOW_MM_H: float = 1.75 # JUDGMENT: grounded drones fly again once rain has stayed under this (0.7 of the blinding rate)...
const DRONE_RESUME_AFTER_S: float = 300.0 # ...for this long

# --- Other effects (JUDGMENT) ------------------------------------------------
## A ground observer's detection range in precipitation, by RATE: [upper bound mm/h, scale]
## pairs, then GROUND_DETECTION_HEAVIEST at and above the last bound. (These are the same
## rate breakpoints as before the standard class names were adopted: the effect follows the
## rate, not the name.)
const GROUND_DETECTION_BY_RATE: Array = [[0.5, 0.9], [1.0, 0.8], [3.0, 0.6]]
const GROUND_DETECTION_HEAVIEST: float = 0.4
const MORTAR_WIND_COUPLING: float = 0.25 # rough shell drift as a fraction of wind x flight time
const MORTAR_WIND_ALTITUDE_M: float = 300.0
## The crew estimates that drift and aims off to cancel it, and the estimate is
## never exact: with MORTAR_CREW_CORRECT_CHANCE it is essentially right, else
## it is off by a random fraction of the drift — under-corrected or over-
## corrected with equal odds (so it averages out, unlike a fixed downwind bias).
## The along-wind error is the main one; a smaller sideways error is a
## misjudged wind direction. About 14 m of average miss at 8 m/s aloft.
const MORTAR_CREW_CORRECT_CHANCE: float = 0.3
const MORTAR_CREW_CORRECT_ERROR_SD: float = 0.05 # of the drift, when the estimate is essentially right
const MORTAR_CREW_MISJUDGE_ERROR_SD: float = 0.30 # of the drift, when it is not
const MORTAR_CREW_DIRECTION_ERROR_SD: float = 0.10 # of the drift, sideways, when it is not

var wind_speed_10m: float = 4.0 # m/s
var wind_from_deg: float = 90.0 # compass bearing the wind blows FROM (0 = north, clockwise)
var temperature_c: float = 4.0
var precip_mm_h: float = 0.0 # liquid-equivalent, 0 when dry
var enabled: bool = true
var battle_started: bool = false

var _wind_z: float = 0.0 # standard normal that wind speed is a Weibull quantile of (a Gaussian copula: AR(1) memory, real Weibull tail)
var _gust_z: float = 0.0
var _wet: bool = false
var _held_class: int = Intensity.NONE
var _shown_mm_h: float = 0.0
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


## The rain class, with hysteresis: the class held so far only changes once the
## intensity is INTENSITY_CLASS_HYSTERESIS past the boundary in question, in either
## direction. (Tracks the calls, so ask it as time goes on — the game does, every frame.)
func intensity_class() -> int:
	if not is_precipitating():
		_held_class = Intensity.NONE
		return _held_class
	var raw: int = _raw_class(precip_mm_h)
	if _held_class == Intensity.NONE:
		_held_class = raw
	while _held_class < raw and precip_mm_h >= _class_lower_edge(_held_class + 1) * (1.0 + INTENSITY_CLASS_HYSTERESIS):
		_held_class += 1
	while _held_class > raw and precip_mm_h < _class_lower_edge(_held_class) * (1.0 - INTENSITY_CLASS_HYSTERESIS):
		_held_class -= 1
	return _held_class


## The intensity (mm/h, to 0.1) for the HUD to show: it stays put until the true value
## has moved a real distance from it (see DISPLAY_HOLD_FRACTION), so it deliberately
## lags the truth a little. Tracks the calls, like intensity_class.
func displayed_intensity_mm_h() -> float:
	if not is_precipitating():
		_shown_mm_h = 0.0
		return 0.0
	if _shown_mm_h <= 0.0 or absf(precip_mm_h - _shown_mm_h) > maxf(DISPLAY_HOLD_MIN_MM_H, DISPLAY_HOLD_FRACTION * _shown_mm_h):
		_shown_mm_h = snappedf(precip_mm_h, 0.1)
	return _shown_mm_h


static func _raw_class(mm_h: float) -> int:
	if mm_h <= DRIZZLE_UP_TO_MM_H:
		return Intensity.DRIZZLE
	if mm_h < LIGHT_BELOW_MM_H:
		return Intensity.LIGHT
	if mm_h < MODERATE_BELOW_MM_H:
		return Intensity.MODERATE
	return Intensity.HEAVY


## The intensity at which `cls` begins (DRIZZLE begins at precipitation itself).
static func _class_lower_edge(cls: int) -> float:
	match cls:
		Intensity.LIGHT: return DRIZZLE_UP_TO_MM_H
		Intensity.MODERATE: return LIGHT_BELOW_MM_H
		Intensity.HEAVY: return MODERATE_BELOW_MM_H
	return INTENSITY_FLOOR_MM_H


func precip_label() -> String:
	var cls: int = intensity_class()
	if cls == Intensity.NONE:
		return ""
	var noun: String = ["", "rain", "sleet", "snow"][precip_type()]
	if cls == Intensity.DRIZZLE:
		# Drizzle is a rain word; the same faint fall as sleet or snow is just light.
		return "Drizzle" if precip_type() == Precip.RAIN else "Light %s" % noun
	var adjective: String = ["", "", "Light", "Moderate", "Heavy"][cls]
	return "%s %s" % [adjective, noun]


## "9°C (48°F)" — the game's units are metric, but the temperature is the one
## reading players most often think of in Fahrenheit, so both are shown.
func temperature_label() -> String:
	return "%d°C (%d°F)" % [roundi(temperature_c), roundi(temperature_c * 9.0 / 5.0 + 32.0)]


func wind_label() -> String:
	return "Wind %d m/s from %s, gusts %d" % [roundi(wind_speed_10m), compass_name(wind_from_deg), roundi(wind_speed_10m * WIND_GUST_RATIO_PEAK)]


static func compass_name(deg: float) -> String:
	return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(roundf(fposmod(deg, 360.0) / 45.0)) % 8]


## One short string that changes whenever anything the HUD shows changes.
func hud_signature() -> String:
	return "%d|%s|%s|%d|%.1f" % [roundi(wind_speed_10m), compass_name(wind_from_deg), precip_label(), roundi(temperature_c), displayed_intensity_mm_h()]


# --- Drone effects ---------------------------------------------------------------

## True once rain/snow is heavy enough that the camera can't see the ground: at or
## above DRONE_BLIND_FROM_MM_H (see there; a rate, not a class).
func drone_vision_blocked() -> bool:
	return is_precipitating() and precip_mm_h >= DRONE_BLIND_FROM_MM_H


## The highest altitude at which the MEAN wind is still within the airframe's
## rating (DRONE_WIND_RATING_MPS) — what a pilot does in a strong wind: fly
## lower, where the wind is weaker (the same power-law shear wind_speed_at
## uses), giving up some sensor coverage (detection range scales with
## altitude, see drone_detection_scale) rather than fighting the full wind
## aloft. Uses the MEAN wind, not the instantaneous gust: a pilot doesn't
## chase every gust up and down. Never above the normal altitude (a calm day
## isn't a reason to climb) or below DRONE_MIN_ALTITUDE_M.
func drone_wind_limited_altitude_m() -> float:
	if wind_speed_at(DRONE_NORMAL_ALTITUDE_M) <= DRONE_WIND_RATING_MPS:
		return DRONE_NORMAL_ALTITUDE_M
	# wind_speed_10m * (z / 10)^k = rating, solved for z.
	return clampf(10.0 * pow(DRONE_WIND_RATING_MPS / wind_speed_10m, 1.0 / WIND_SHEAR_EXPONENT), DRONE_MIN_ALTITUDE_M, DRONE_NORMAL_ALTITUDE_M)


## Where the drone actually flies: the lower of the rain altitude (in rain it
## flies lower to see through it, more so the harder it falls) and the wind
## altitude above (JUDGMENT: no cited pilot practice for the exact rule —
## the rating is the one sourced number, DJI's own).
func drone_operating_altitude_m() -> float:
	var altitude: float = DRONE_NORMAL_ALTITUDE_M
	if is_precipitating():
		altitude = clampf(DRONE_NORMAL_ALTITUDE_M * exp(-DRONE_ALTITUDE_DECAY_PER_MM_H * precip_mm_h), DRONE_MIN_ALTITUDE_M, DRONE_NORMAL_ALTITUDE_M)
	return minf(altitude, drone_wind_limited_altitude_m())


## Multiplies the drone's detection range: it scales with altitude (a lower
## drone sees a smaller patch), and is nothing at all once vision is blocked.
func drone_detection_scale() -> float:
	if drone_vision_blocked():
		return 0.0
	return drone_operating_altitude_m() / DRONE_NORMAL_ALTITUDE_M


## Multiplies a GROUND observer's detection range.
func ground_detection_scale() -> float:
	if not is_precipitating():
		return 1.0
	for pair in GROUND_DETECTION_BY_RATE:
		if precip_mm_h < pair[0]:
			return pair[1]
	return GROUND_DETECTION_HEAVIEST


## Flight time on a full battery, as a fraction of its rated value.
func drone_cold_flight_time_factor() -> float:
	return maxf(DRONE_COLD_FLIGHT_TIME_FLOOR, 1.0 - DRONE_COLD_FLIGHT_TIME_LOSS_PER_DEGREE * maxf(0.0, DRONE_COLD_CAPACITY_ONSET_C - temperature_c))


func _drone_precip_type_factor() -> float:
	return DRONE_DRY_SNOW_HAZARD_FACTOR if is_precipitating() and temperature_c < DRY_SNOW_BELOW_C else 1.0


## Per-flight-minute chance of a failure. Baseline x wind x cold x (below
## DRONE_BLIND_FROM_MM_H) precipitation; at or above it the drone is on a forced
## flight home, and the wet adds its own per-minute hazard instead.
func drone_hazard_per_minute(altitude_m: float) -> float:
	var base: float = DRONE_BASE_FAILURES_PER_FLIGHT_HOUR / 60.0
	var wind: float = wind_speed_at(altitude_m) * gust_multiplier(altitude_m)
	var wind_mult: float = 1.0 + DRONE_WIND_HAZARD_SCALE * pow(wind / DRONE_WIND_RATING_MPS, DRONE_WIND_HAZARD_EXPONENT)
	var cold_mult: float = 1.0 + DRONE_COLD_HAZARD_PER_DEGREE * maxf(0.0, DRONE_COLD_CAPACITY_ONSET_C - temperature_c)
	var hazard: float = base * wind_mult * cold_mult
	if is_precipitating():
		if drone_vision_blocked():
			hazard += DRONE_WET_RETURN_HAZARD_PER_MIN * pow(precip_mm_h, DRONE_RETURN_HAZARD_EXPONENT) * _drone_precip_type_factor()
		else:
			hazard *= 1.0 + DRONE_RAIN_HAZARD_SCALE * pow(precip_mm_h, DRONE_PRECIP_HAZARD_EXPONENT) * _drone_precip_type_factor()
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

## How far the wind would carry a round in flight for `flight_time_s` seconds,
## in SCREEN PIXELS, if nobody corrected for it. Shells drift downwind.
func mortar_wind_drift_px(flight_time_s: float) -> Vector2:
	var wind_m: Vector2 = wind_velocity_mps(MORTAR_WIND_ALTITUDE_M, false)
	return wind_m * flight_time_s * MORTAR_WIND_COUPLING * GameConfig.PIXELS_PER_METER


## The drift a crew THINKS it has to cancel at the start of a fire mission:
## the true drift plus a random error (see MORTAR_CREW_* above) — right, under,
## or over, with sideways error from misjudging the direction. Drawn from the
## weather's own random stream. BattleManager keeps it for the whole mission,
## so a wind that later changes leaves the crew correcting for the old one.
func crew_wind_estimate_px(flight_time_s: float) -> Vector2:
	var drift: Vector2 = mortar_wind_drift_px(flight_time_s)
	if drift.length() < 0.001:
		return drift
	var right: bool = rng.randf() < MORTAR_CREW_CORRECT_CHANCE
	var along_sd: float = MORTAR_CREW_CORRECT_ERROR_SD if right else MORTAR_CREW_MISJUDGE_ERROR_SD
	var cross_sd: float = 0.0 if right else MORTAR_CREW_DIRECTION_ERROR_SD
	var along: Vector2 = drift.normalized()
	return drift * (1.0 + rng.randfn(0.0, along_sd)) + along.orthogonal() * drift.length() * rng.randfn(0.0, cross_sd)


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
