class_name NetDebugOverlay
extends CanvasLayer
## Compact network diagnostics: ping, loss, tick error, correction count and
## estimated bandwidth. Updates at 4 Hz, never per frame.

var net: Node
var prediction: PredictionController
var _panel: PanelContainer
var _label: Label
var _timer: Timer
var _bytes_in_window: int = 0
var _bytes_out_window: int = 0
var _last_in_total: int = 0
var _last_out_total: int = 0
var _window_start: float = 0.0
var _kbps_in: float = 0.0
var _kbps_out: float = 0.0


func _ready() -> void:
	layer = 20
	_build()
	_timer = Timer.new()
	_timer.wait_time = 0.25
	_timer.autostart = true
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	_window_start = Time.get_ticks_msec() / 1000.0


func setup(net_ref: Node, prediction_ref: PredictionController = null) -> void:
	net = net_ref
	prediction = prediction_ref
	visible = net != null and (not net.is_offline or net.simulated_latency_ms > 0)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -330.0
	_panel.offset_top = 12.0
	_panel.offset_right = -12.0
	_panel.offset_bottom = 132.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.02, 0.05, 0.78)
	style.border_color = Color(0.2, 0.8, 1.0, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	_panel.add_child(_label)


func record_bytes(direction_in: int, direction_out: int) -> void:
	_bytes_in_window += direction_in
	_bytes_out_window += direction_out


func _refresh() -> void:
	if net == null or not is_instance_valid(net):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = maxf(now - _window_start, 0.001)
	if net.has_method("bandwidth_bytes"):
		var totals: Vector2i = net.bandwidth_bytes()
		_bytes_in_window += maxi(totals.x - _last_in_total, 0)
		_bytes_out_window += maxi(totals.y - _last_out_total, 0)
		_last_in_total = totals.x
		_last_out_total = totals.y
	_kbps_in = float(_bytes_in_window) / 1024.0 / elapsed
	_kbps_out = float(_bytes_out_window) / 1024.0 / elapsed
	_bytes_in_window = 0
	_bytes_out_window = 0
	_window_start = now
	var ping: int = net.get_ping_ms()
	var loss: float = net.get_packet_loss() * 100.0
	var tick_error: int = 0
	var corrections: int = 0
	var error_m: float = 0.0
	if prediction != null and prediction.car != null:
		tick_error = Engine.get_physics_frames() - prediction.last_server_tick if prediction.last_server_tick >= 0 else 0
		corrections = prediction.corrections
		error_m = prediction.last_snapshot_error
	_label.text = "NET  %s\nPing %d ms   Loss %.1f%%\nTick err %d   Pred err %.2f m\nCorrections %d\nIn %.1f KB/s  Out %.1f KB/s" % [
		"OFFLINE" if net.is_offline else ("HOST" if net.is_server else "CLIENT"),
		ping, loss, tick_error, error_m, corrections, _kbps_in, _kbps_out,
	]
