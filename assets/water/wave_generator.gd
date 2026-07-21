@tool
class_name WaveGenerator extends Node

const G := 9.81
const DEPTH := 20.0

var map_size : int
var context : RenderingContext
var pipelines : Dictionary
var descriptors : Dictionary

var pass_parameters : Array[WaveCascadeParameters]
var pass_num_cascades_remaining : int

func init_gpu(num_cascades : int) -> void:
	if not context: context = RenderingContext.create(RenderingServer.get_rendering_device())
	var spectrum_compute_shader := context.load_shader('res://assets/shaders/compute/spectrum_compute.glsl')
	var fft_butterfly_shader := context.load_shader('res://assets/shaders/compute/fft_butterfly.glsl')
	var spectrum_modulate_shader := context.load_shader('res://assets/shaders/compute/spectrum_modulate.glsl')
	var fft_compute_shader := context.load_shader('res://assets/shaders/compute/fft_compute.glsl')
	var transpose_shader := context.load_shader('res://assets/shaders/compute/transpose.glsl')
	var fft_unpack_shader := context.load_shader('res://assets/shaders/compute/fft_unpack.glsl')

	var dims := Vector2i(map_size, map_size)
	var num_fft_stages := int(log(map_size) / log(2))

	descriptors[&'spectrum'] = context.create_texture(dims, RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT, num_cascades)
	descriptors[&'butterfly_factors'] = context.create_storage_buffer(num_fft_stages*map_size * 4 * 4)
	descriptors[&'fft_buffer'] = context.create_storage_buffer(num_cascades * map_size*map_size * 4*2 * 2 * 4)
	descriptors[&'displacement_map'] = context.create_texture(
		dims,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT,
		num_cascades
	)
	descriptors[&'normal_map'] = context.create_texture(dims, RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT, num_cascades)

	var spectrum_set := context.create_descriptor_set([descriptors[&'spectrum']], spectrum_compute_shader, 0)
	var fft_butterfly_set := context.create_descriptor_set([descriptors[&'butterfly_factors']], fft_butterfly_shader, 0)
	var fft_compute_set := context.create_descriptor_set([descriptors[&'butterfly_factors'], descriptors[&'fft_buffer']], fft_compute_shader, 0)
	var transpose_set := context.create_descriptor_set([descriptors[&'butterfly_factors'], descriptors[&'fft_buffer']], transpose_shader, 0)
	var spectrum_modulate_tex_set := context.create_texture_set(descriptors[&'spectrum'], context.linear_sampler, spectrum_modulate_shader, 0, 0)
	var modulate_fft_set := context.create_descriptor_set([descriptors[&'fft_buffer']], spectrum_modulate_shader, 1)
	var unpack_fft_set := context.create_descriptor_set([descriptors[&'fft_buffer']], fft_unpack_shader, 1)
	var unpack_set := context.create_descriptor_set([descriptors[&'displacement_map'], descriptors[&'normal_map']], fft_unpack_shader, 0)

	pipelines[&'spectrum_compute'] = context.create_pipeline([map_size/16, map_size/16, 1], [spectrum_set], spectrum_compute_shader)
	pipelines[&'spectrum_modulate'] = context.create_pipeline([map_size/16, map_size/16, 1], [spectrum_modulate_tex_set, modulate_fft_set], spectrum_modulate_shader)
	pipelines[&'fft_butterfly'] = context.create_pipeline([map_size/2/64, num_fft_stages, 1], [fft_butterfly_set], fft_butterfly_shader)
	pipelines[&'fft_compute'] = context.create_pipeline([1, map_size, 4], [fft_compute_set], fft_compute_shader)
	pipelines[&'transpose'] = context.create_pipeline([map_size/32, map_size/32, 4], [transpose_set], transpose_shader)
	pipelines[&'fft_unpack'] = context.create_pipeline([map_size/16, map_size/16, 1], [unpack_set, unpack_fft_set], fft_unpack_shader)

	var compute_list := context.compute_list_begin()
	pipelines[&'fft_butterfly'].call(context, compute_list)
	context.compute_list_end()

func get_displacement_map_rid(cascade:int) -> RID:
	return descriptors[&'displacement_map'].rid

func get_displacement_map_image(cascade:int = 0, img:Image = null) -> Image:
	var tex_rid := get_displacement_map_rid(cascade)
	var data := context.device.texture_get_data(tex_rid, 0)
	var bytes_per_pixel = 8
	var layer_size = map_size * map_size * bytes_per_pixel
	var layer_offset = cascade * layer_size
	var layer_data = data.slice(layer_offset, layer_offset + layer_size)
	if img == null:
		img = Image.create_from_data(map_size, map_size, false, Image.FORMAT_RGBAH, layer_data)
	else:
		img.set_data(map_size, map_size, false, Image.FORMAT_RGBAH, layer_data)
	return img

func retrieve_displacement_map(cascade:int, img:Image = null) -> Image:
	var displacement_img := get_displacement_map_image(cascade, img)
	displacement_img.convert(Image.FORMAT_RGBAF)
	return displacement_img

func _process(delta: float) -> void:
	if pass_num_cascades_remaining == 0: return
	pass_num_cascades_remaining -= 1

	var compute_list := context.compute_list_begin()
	_update(compute_list, pass_num_cascades_remaining, pass_parameters)
	context.compute_list_end()

func _update(compute_list : int, cascade_index : int, parameters : Array[WaveCascadeParameters]) -> void:
	var params := parameters[cascade_index]
	if params.should_generate_spectrum:
		var alpha := JONSWAP_alpha(params.wind_speed, params.fetch_length*1e3)
		var omega := JONSWAP_peak_angular_frequency(params.wind_speed, params.fetch_length*1e3)
		pipelines[&'spectrum_compute'].call(context, compute_list, RenderingContext.create_push_constant([params.spectrum_seed.x, params.spectrum_seed.y, params.tile_length.x, params.tile_length.y, alpha, omega, params.wind_speed, deg_to_rad(params.wind_direction), DEPTH, params.swell, params.detail, params.spread, cascade_index]))
		params.should_generate_spectrum = false
	pipelines[&'spectrum_modulate'].call(context, compute_list, RenderingContext.create_push_constant([params.tile_length.x, params.tile_length.y, DEPTH, params.time, cascade_index]))

	var fft_push_constant := RenderingContext.create_push_constant([cascade_index])
	pipelines[&'fft_compute'].call(context, compute_list, fft_push_constant)
	pipelines[&'transpose'].call(context, compute_list, fft_push_constant)
	context.compute_list_add_barrier(compute_list)
	pipelines[&'fft_compute'].call(context, compute_list, fft_push_constant)

	pipelines[&'fft_unpack'].call(context, compute_list, RenderingContext.create_push_constant([cascade_index, params.whitecap, params.foam_grow_rate, params.foam_decay_rate]))

func update(delta : float, parameters : Array[WaveCascadeParameters]) -> void:
	assert(parameters.size() != 0)
	if not context:
		init_gpu(maxi(2, len(parameters)))
	elif pass_num_cascades_remaining != 0:
		var compute_list := context.compute_list_begin()
		for i in range(pass_num_cascades_remaining):
			_update(compute_list, i, pass_parameters)
		context.compute_list_end()

	for i in len(parameters):
		var params := parameters[i]
		params.time += delta
		params.foam_grow_rate = delta * params.foam_amount*7.5
		params.foam_decay_rate = delta * maxf(0.5, 10.0 - params.foam_amount)*1.15

	pass_parameters = parameters
	pass_num_cascades_remaining = len(parameters)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if context: context.free()

static func JONSWAP_alpha(wind_speed:=20.0, fetch_length:=550e3) -> float:
	return 0.076 * pow(wind_speed**2 / (fetch_length*G), 0.22)

static func JONSWAP_peak_angular_frequency(wind_speed:=20.0, fetch_length:=550e3) -> float:
	return 22.0 * pow(G*G / (wind_speed*fetch_length), 1.0/3.0)
