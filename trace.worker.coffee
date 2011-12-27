# TODO
# - shadow
# - textures
# - perlin
# - texture cut
# - opacity
# - reflect
# - refract
# - bump

# TO FIX
# - pb de rotation des groupes (pokeball)
# - refraction des planes plafond du mauvais cote (origin.rt)

Array::contains = (x) -> (@indexOf x) != -1
log = (x...) -> postMessage ['log', x...]
copy = (obj) ->
	if Array.isArray obj
		obj.slice()
	else if obj instanceof Object and not (obj instanceof Function)
		new_obj = {}
		for key, val of obj
			new_obj[key] = copy val
		new_obj
	else
		obj


class Parser
	objectify: (pairs) ->
		hash = {}
		for [key, value] in pairs
			if @multiple.contains key
				if key not of hash
					hash[key] = []
				hash[key].push value
			else
				hash[key] = value
		hash

	multiple: ['light', 'item', 'group']
	convert:
		color: (input) -> input[0].match(/(..)/g).map (hex) -> (parseInt hex, 16) / 255
		color2: (input) -> input[0].match(/(..)/g).map (hex) -> (parseInt hex, 16) / 255
		l_color: (input) -> input[0].match(/(..)/g).map (hex) -> (parseInt hex, 16) / 255
		tex: (input) -> input[0]
		radius: (input) -> +input[0]
		width: (input) -> +input[0]
		height: (input) -> +input[0]
		highdef: (input) -> input.map (x) -> +x
		checkerboard: (input) -> +input[0]
		distscreen: (input) -> +input[0]
		brightness: (input) -> +input[0]
		group_id: (input) -> input[0]
		id: (input) -> +input[0]
		max_reflect: (input) -> +input[0]
		tex_rep: (input) -> +input[0]
		tex_coef: (input) -> +input[0]
		size_mul: (input) -> +input[0]
		reflect: (input) -> +input[0]
		l_intensity: (input) -> +input[0]
		coords: (input) -> input.map (x) -> +x
		limits: (input) -> input.map (x) -> +x
		rot: (input) -> input.map (x) -> +x
		type: (input) -> input[0]

	constructor: (str) ->
		@lines = str
			.replace(/\#[^\n]*/g, '')
			.replace(/\{/g, '\n{')
			.split('\n')
			.map((line) -> line.trim())
			.filter((line) -> line)

	parse: ->
		@objectify(while block = @parseBlock()
			block
		)

	parseBlock: ->
		name = @lines.shift()
		return if not name
		@lines.shift() # {
		params = @objectify(while line = @lines.shift()
			break if line == '}'
			[key, values...] = line.split /\s+/
			if key of @convert
				values = @convert[key] values
			[key, values]
		)
		[name, params]



scene = 0
textures = []
textures_remaining = 0

@onmessage = (data: [type, value]) ->
	if type == 'process'
		{input} = value
		scene = new Parser(input).parse()

#		log scene
		scene.global.highdef ?= []
		scene.global.highdef[0] ?= 1 # upscale
		scene.global.highdef[1] ?= 0 # randomRays
		scene.global.distscreen ?= 1000
		scene.global.max_reflect ?= 10
		scene.global.l_color ?= [0, 0, 0]
		scene.global.l_intensity = (scene.global.l_intensity ? 0) / 100
		vec3.scale scene.global.l_color, scene.global.l_intensity
		scene.eye.rot = vec3.scale (scene.eye.rot ? [0, 0, 0]), Math.PI / 180
		[scene.global.upscale, scene.global.randomRays] = scene.global.highdef

		scene.global.W = scene.global.width * scene.global.upscale
		scene.global.H = scene.global.height * scene.global.upscale
		postMessage ['resize', {
			W: scene.global.W,
			H: scene.global.H,
			realW: scene.global.width,
			realH: scene.global.height}]

		groups = {}

		for light in scene.light || []
			light.coords ?= [0, 0, 0]
			light.color ?= [1, 1, 1]

		for item in scene.item
			item.color2 ?= [0, 0, 0]
			item.coords ?= [0, 0, 0]
			item.rot = vec3.scale (item.rot ? [0, 0, 0]), Math.PI / 180
			item.brightness = (item.brightness ? 0) / 100
			item.intensity = (item.intensity ? 100) / 100
			item.reflect = (item.reflect ? 0) / 100
			item.radius ?= 2
			item.limits ?= [0, 0, 0, 0, 0, 0]
			for i in [0 ... 3]
				if item.limits[2 * i] >= item.limits[2 * i + 1]
					item.limits[2 * i] = -Infinity
					item.limits[2 * i + 1] = Infinity

			item.transform = mat4.identity()
			mat4.translate item.transform, item.coords
			mat4.rotateX item.transform, item.rot[0]
			mat4.rotateY item.transform, item.rot[1]
			mat4.rotateZ item.transform, item.rot[2]

			if item.type == 'plane'
				item.normal = vec3.normalize vec3.rotateXYZ [0, 0, 1], item.rot...

			item.intersect = intersects[item.type]
			if item.group_id
				groups[item.group_id] ?= []
				groups[item.group_id].push item

		for group in scene.group || []
			group.size_mul ?= 1
			group.rot = vec3.scale (group.rot ? [0, 0, 0]), Math.PI / 180
			group.coords ?= [0, 0, 0]

			group.transform = mat4.identity()
			mat4.scale group.transform, [group.size_mul, group.size_mul, group.size_mul]
			mat4.translate group.transform, group.coords
			mat4.rotateX group.transform, group.rot[0]
			mat4.rotateY group.transform, group.rot[1]
			mat4.rotateZ group.transform, group.rot[2]

			if group.id not of groups
				continue

			for item_raw in groups[group.id]
				item = copy item_raw
				delete item.group_id

				t = mat4.create group.transform
				mat4.multiply t, item.transform
				item.transform = t

				if item.normal?
					item.normal = vec3.rotateXYZ item.normal, item.rot...

				if item.radius?
					item.radius *= group.size_mul

				scene.item.push item

		scene.item = scene.item.filter (item) -> not item.group_id?

		textures_remaining = 1
		for item in scene.item
			item.coords = mat4.multiplyVec4 item.transform, [0, 0, 0, 1]
			item.inverse = mat4.inverse item.transform, mat4.create()
			item.radius2 = item.radius * item.radius

			if item.tex?
				item.tex_rep ?= 0
				item.tex_coef ?= 1
				postMessage ['texture', item.tex]
				textures_remaining++

		@onmessage data: ['texture']
#		log scene.item

	if type == 'texture'
		textures_remaining--

		if value
			{name, content} = value
			textures[name] = content

		if textures_remaining == 0
			for y in [0 ... scene.global.H]
				result = ['result']
				result.push y
				for x in [0 ... scene.global.W]
					color = process x, y, scene.global.upscale, scene.global.randomRays
					result.push ~~(color[0] * 255)
					result.push ~~(color[1] * 255)
					result.push ~~(color[2] * 255)

				postMessage result

epsilon = 0.0001

mod1 = (x) ->
	if x < 0
		(.5 + Math.abs x) % 1
	else
		x % 1

mod = (x, n) ->
	((x % n) + n) % n

inLimits = (limits, pos_) ->
	limits[0] <= pos_[0] <= limits[1] and
	limits[2] <= pos_[1] <= limits[3] and
	limits[4] <= pos_[2] <= limits[5]

isValid = (ray, distances, item, min_distance) ->
	for distance in distances
		if not (0 < distance < min_distance)
			continue

		pos = vec3.create()
		pos = vec3.add ray.origin, (vec3.scale ray.dir, distance, pos), pos
		pos_ = mat4.multiplyVec3 item.inverse, pos, vec3.create()
		if inLimits item.limits, pos_
			return [pos, pos_, distance]
	[null, null, null]

solve_eq2 = (a, b, c) ->
	delta = b * b - 4 * a * c
	if delta < 0
		return []

	sqDelta = Math.sqrt delta
	[(-b - sqDelta) / (2 * a),
	 (-b + sqDelta) / (2 * a)]

intersects =
	plane: (ray, ray_, item, min_distance) ->
		solutions = []
		if ray_.dir[2] != 0
			solutions = [-ray_.origin[2] / ray_.dir[2]]

		[pos, pos_, distance] = isValid ray, solutions, item, min_distance
		return if not pos

		color = item.color

		if item.checkerboard?
			if (mod1(pos_[0] / item.checkerboard) > 0.5) == (mod1(pos_[1] / item.checkerboard) > 0.5)
				color = item.color2

		if item.tex?
			texture = textures[item.tex]
			x = texture.width / 2 - ~~pos_[1]
			y = texture.height / 2 - ~~pos_[0]
			if item.tex_rep
				x = mod x * item.tex_coef, texture.width
				y = mod y * item.tex_coef, texture.height
			idx = (texture.width * y + x) * 4
			color = [texture.data[idx] / 255, texture.data[idx + 1] / 255, texture.data[idx + 2] / 255]

		normal = vec3.normalize mat4.multiplyDelta3 item.transform, [0, 0, 1]
#		normal = item.normal
		{distance, pos, normal, color, item}

	sphere: (ray, ray_, item, min_distance) ->
		a = vec3.dot ray_.dir, ray_.dir
		b = 2 * vec3.dot ray_.origin, ray_.dir
		c = (vec3.dot ray_.origin, ray_.origin) - item.radius2
		[pos, pos_, distance] = isValid ray, solve_eq2(a, b, c), item, min_distance
		return if not pos

		color = item.color
		if item.checkerboard?
			phi = Math.acos (pos_[2] / item.radius)
			x = phi / Math.PI * 500
			theta = Math.acos((pos_[1] / item.radius) / Math.sin(phi)) / (2 * Math.PI);
			if (pos_[0] < 0)
				y = theta * 500;
			else
				y = (1 - theta) * 500

			if (mod1(x / item.checkerboard) > 0.5) == (mod1(y / item.checkerboard) > 0.5)
				color = item.color2

		normal = vec3.normalize vec3.sub pos, item.coords, vec3.create()
		{distance, pos, normal, color, item}

	cone: (ray, ray_, item, min_distance) ->
		a = ray_.dir[0] * ray_.dir[0] + ray_.dir[1] * ray_.dir[1] -
			item.radius * ray_.dir[2] * ray_.dir[2]
		b = 2 * (ray_.origin[0] * ray_.dir[0] + ray_.origin[1] * ray_.dir[1] -
			item.radius * ray_.origin[2] * ray_.dir[2])
		c = ray_.origin[0] * ray_.origin[0] + ray_.origin[1] * ray_.origin[1] -
			item.radius * ray_.origin[2] * ray_.origin[2]
		[pos, pos_, distance] = isValid ray, solve_eq2(a, b, c), item, min_distance
		return if not pos

		color = item.color
		normal = mat4.multiplyVec3 item.inverse, vec3.create pos
		normal[2] = -normal[2] * Math.tan item.radius2
		normal = vec3.normalize mat4.multiplyDelta3 item.transform, normal
		{distance, pos, normal, color, item}

	cylinder: (ray, ray_, item, min_distance) ->
		a = ray_.dir[0] * ray_.dir[0] + ray_.dir[1] * ray_.dir[1]
		b = 2 * (ray_.origin[0] * ray_.dir[0] + ray_.origin[1] * ray_.dir[1])
		c = ray_.origin[0] * ray_.origin[0] + ray_.origin[1] * ray_.origin[1] - item.radius2
		[pos, pos_, distance] = isValid ray, solve_eq2(a, b, c), item, min_distance
		return if not pos

		color = item.color
		normal = mat4.multiplyVec3 item.inverse, vec3.create pos
		normal[2] = 0
		normal = vec3.normalize mat4.multiplyDelta3 item.transform, normal
		{distance, pos, normal, color, item}


intersect = (ray, min_distance=Infinity) ->
	min_isect = null

	for item in scene.item
		ray_ =
			dir: (vec3.normalize mat4.multiplyDelta3 item.inverse, ray.dir)
			origin: (mat4.multiplyVec3 item.inverse, ray.origin, [0, 0, 0])

		isect = item.intersect ray, ray_, item, min_distance
		if isect and (not min_isect or isect.distance < min_isect.distance)
			min_isect = isect
			min_distance = isect.distance

	min_isect

lightning = (isect) ->
	if scene.light?
		color = [0, 0, 0]
	else
		color = vec3.create isect.color

	f = false
	for light in scene.light || []
		dir = vec3.sub light.coords, isect.pos, vec3.create()
		min_distance = vec3.length dir
		vec3.normalize dir
		pos = vec3.create()
		pos = vec3.add isect.pos, (vec3.scale dir, epsilon, pos), pos
		ray =
			origin: pos
			dir: dir

		if not intersect ray, min_distance
			shade = Math.abs vec3.dot isect.normal, ray.dir
			# intensity * dot * light * (c + brightness)
			add_color = vec3.create isect.color
			add_color = vec3.plus add_color, isect.item.brightness
			add_color = vec3.mul add_color, light.color
			vec3.scale add_color, shade
			add_color = vec3.scale add_color, isect.item.intensity

			vec3.add color, add_color
			f = true

	ambiant = vec3.create isect.color
	vec3.mul ambiant, scene.global.l_color
	vec3.add color, ambiant
	color

process = (x, y, upscale, randomRays) ->
	color = [0, 0, 0]

	vec3.add color, processRay(
		(scene.global.W / 2 - x) / upscale,
		(scene.global.H / 2 - y) / upscale)

	for i in [0 ... randomRays]
		vec3.add color, processRay(
			(scene.global.W / 2 - x + Math.random() - 0.5) / upscale,
			(scene.global.H / 2 - y + Math.random() - 0.5) / upscale)

	vec3.scale color, 1 / (1 + randomRays)

processRay = (x, y) ->
	ray =
		origin: vec3.create scene.eye.coords
		dir: vec3.normalize [scene.global.distscreen, x, y]

	ray.dir = vec3.rotateXYZ ray.dir, scene.eye.rot...

	colors = []

	for i in [0 ... scene.global.max_reflect]
		isect = intersect ray
		if not isect
			break

		colors.push
			color: lightning isect
			reflect: isect.item.reflect

		if isect.item.reflect == 0
			break

		ray.origin = vec3.add isect.pos, (vec3.scale isect.normal, epsilon, ray.origin), ray.origin
		ray.dir = vec3.reflect ray.dir, (vec3.normalize isect.normal), vec3.create()

	colors.reverse()
	finalColor = [0, 0, 0]
	for c in colors
		finalColor = vec3.mix finalColor, c.color, 1 - c.reflect
	finalColor

`
var cos=Math.cos, sin=Math.sin;
vec3={
	create:function(a){var b=new Array(3);a?(b[0]=a[0],b[1]=a[1],b[2]=a[2]):b[0]=b[1]=b[2]=0;return b},
	set:function(a,b){b[0]=a[0];b[1]=a[1];b[2]=a[2];return b},
	add:function(a,b,c){if(!c||a===c)return a[0]+=b[0],a[1]+=b[1],a[2]+=b[2],a;c[0]=a[0]+b[0];c[1]=a[1]+b[1];c[2]=a[2]+b[2];return c},
	mul:function(a,b,c){if(!c||a===c)return a[0]*=b[0],a[1]*=b[1],a[2]*=b[2],a;c[0]=a[0]*b[0];c[1]=a[1]*b[1];c[2]=a[2]*b[2];return c},
	sub:function(a,b,c){if(!c||a===c)return a[0]-=b[0],a[1]-=b[1],a[2]-=b[2],a;c[0]=a[0]-b[0];c[1]=a[1]-b[1];c[2]=a[2]-b[2];return c},
	negate:function(a,b){b||(b=a);b[0]=-a[0];b[1]=-a[1];b[2]=-a[2];return b},
	scale:function(a,b,c){if(!c||a===c)return a[0]*=b,a[1]*=b,a[2]*=b,a;c[0]=a[0]*b;c[1]=a[1]*b;c[2]=a[2]*b;return c},
	plus:function(a,b,c){if(!c||a===c)return a[0]+=b,a[1]+=b,a[2]+=b,a;c[0]=a[0]+b;c[1]=a[1]+b;c[2]=a[2]+b;return c},
	normalize:function(a,b){b||(b=a);var c=a[0],e=a[1],f=a[2],d=Math.sqrt(c*c+e*e+f*f);if(d){if(1===d)return b[0]=c,b[1]=e,b[2]=f,b}else return b[0]=0,b[1]=0,b[2]=0,b;d=1/d;b[0]=c*d;b[1]=e*d;b[2]=f*d;return b},
	cross:function(a,b,c){c||(c=a);var e=a[0],f=a[1],a=a[2],d=b[0],g=b[1],b=b[2];c[0]=f*b-a*g;c[1]=a*d-e*b;c[2]=e*g-f*d;return c},
	dot:function(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]},
	str:function (a) {return '['+a[0]+', '+a[1]+', '+a[2]+']'},
	length:function (vec) { var x = vec[0], y = vec[1], z = vec[2]; return Math.sqrt(x * x + y * y + z * z);},
	reflect:function(i,n,r){return vec3.sub(i,vec3.scale(n,2*vec3.dot(n,i),r),r)},
	rotateXYZ:function(v,x,y,z){
		var m=mat4.create(mat4.identity());
		mat4.rotateX(m,x);
		mat4.rotateY(m,y);
		mat4.rotateZ(m,z);
		return mat4.multiplyVec3(m,v);
	},
	rotateZYX:function(v,x,y,z){
		var m=mat4.create(mat4.identity());
		mat4.rotateZ(m,z);
		mat4.rotateY(m,y);
		mat4.rotateX(m,x);
		return mat4.multiplyVec3(m,v);
	},
	mix:function(x,y,a){
		return vec3.add(
			vec3.scale(x,1-a,vec3.create()),
			vec3.scale(y,a,vec3.create()),
			vec3.create());
	}
}
mat4={
	create:function(a){var b=new Array(16);a&&(b[0]=a[0],b[1]=a[1],b[2]=a[2],b[3]=a[3],b[4]=a[4],b[5]=a[5],b[6]=a[6],b[7]=a[7],b[8]=a[8],b[9]=a[9],b[10]=a[10],b[11]=a[11],b[12]=a[12],b[13]=a[13],b[14]=a[14],b[15]=a[15]);return b},
	identity:function(a){a||(a=mat4.create());a[0]=1;a[1]=0;a[2]=0;a[3]=0;a[4]=0;a[5]=1;a[6]=0;a[7]=0;a[8]=0;a[9]=0;a[10]=1;a[11]=0;a[12]=0;a[13]=0;a[14]=0;a[15]=1;return a},
	multiplyVec3:function(a,b,c){c||(c=b);var d=b[0],e=b[1],b=b[2];c[0]=a[0]*d+a[4]*e+a[8]*b+a[12];c[1]=a[1]*d+a[5]*e+a[9]*b+a[13];c[2]=a[2]*d+a[6]*e+a[10]*b+a[14];return c},
	multiplyVec4:function(a,b,c){c||(c=b);var d=b[0],e=b[1],f=b[2],b=b[3];c[0]=a[0]*d+a[4]*e+a[8]*f+a[12]*b;c[1]=a[1]*d+a[5]*e+a[9]*f+a[13]*b;c[2]=a[2]*d+a[6]*e+a[10]*f+a[14]*b;c[3]=a[3]*d+a[7]*e+a[11]*f+a[15]*b;return c},
	multiplyDelta3: function(mat, vec) {
		var a_ = mat4.multiplyVec3(mat, [0, 0, 0]);
		var b_ = mat4.multiplyVec3(mat, vec3.create(vec));
		return vec3.sub(b_, a_);
	},
	rotateX:function(b,c,a){var d=Math.sin(c),c=Math.cos(c),e=b[4],f=b[5],g=b[6],h=b[7],i=b[8],j=b[9],k=b[10],l=b[11];a?b!==a&&(a[0]=b[0],a[1]=b[1],a[2]=b[2],a[3]=b[3],a[12]=b[12],a[13]=b[13],a[14]=b[14],a[15]=b[15]):a=b;a[4]=e*c+i*d;a[5]=f*c+j*d;a[6]=g*c+k*d;a[7]=h*c+l*d;a[8]=e*-d+i*c;a[9]=f*-d+j*c;a[10]=g*-d+k*c;a[11]=h*-d+l*c;return a},
	rotateY:function(b,c,a){var d=Math.sin(c),c=Math.cos(c),e=b[0],f=b[1],g=b[2],h=b[3],i=b[8],j=b[9],k=b[10],l=b[11];a?b!==a&&(a[4]=b[4],a[5]=b[5],a[6]=b[6],a[7]=b[7],a[12]=b[12],a[13]=b[13],a[14]=b[14],a[15]=b[15]):a=b;a[0]=e*c+i*-d;a[1]=f*c+j*-d;a[2]=g*c+k*-d;a[3]=h*c+l*-d;a[8]=e*d+i*c;a[9]=f*d+j*c;a[10]=g*d+k*c;a[11]=h*d+l*c;return a},
	rotateZ:function(b,c,a){var d=Math.sin(c),c=Math.cos(c),e=b[0],f=b[1],g=b[2],h=b[3],i=b[4],j=b[5],k=b[6],l=b[7];a?b!==a&&(a[8]=b[8],a[9]=b[9],a[10]=b[10],a[11]=b[11],a[12]=b[12],a[13]=b[13],a[14]=b[14],a[15]=b[15]):a=b;a[0]=e*c+i*d;a[1]=f*c+j*d;a[2]=g*c+k*d;a[3]=h*c+l*d;a[4]=e*-d+i*c;a[5]=f*-d+j*c;a[6]=g*-d+k*c;a[7]=h*-d+l*c;return a},
	translate:function(a,c,b){var d=c[0],e=c[1],c=c[2],f,g,h,i,j,k,l,m,n,o,p,q;if(!b||a===b)return a[12]=a[0]*d+a[4]*e+a[8]*c+a[12],a[13]=a[1]*d+a[5]*e+a[9]*c+a[13],a[14]=a[2]*d+a[6]*e+a[10]*c+a[14],a[15]=a[3]*d+a[7]*e+a[11]*c+a[15],a;f=a[0];g=a[1];h=a[2];i=a[3];j=a[4];k=a[5];l=a[6];m=a[7];n=a[8];o=a[9];p=a[10];q=a[11];b[0]=f;b[1]=g;b[2]=h;b[3]=i;b[4]=j;b[5]=k;b[6]=l;b[7]=m;b[8]=n;b[9]=o;b[10]=p;b[11]=q;b[12]=f*d+j*e+n*c+a[12];b[13]=g*d+k*e+o*c+a[13];b[14]=h*d+l*e+p*c+a[14];b[15]=i*d+m*e+q*c+a[15];return b},
	scale:function(a,c,b){var d=c[0],e=c[1],c=c[2];if(!b||a===b)return a[0]*=d,a[1]*=d,a[2]*=d,a[3]*=d,a[4]*=e,a[5]*=e,a[6]*=e,a[7]*=e,a[8]*=c,a[9]*=c,a[10]*=c,a[11]*=c,a;b[0]=a[0]*d;b[1]=a[1]*d;b[2]=a[2]*d;b[3]=a[3]*d;b[4]=a[4]*e;b[5]=a[5]*e;b[6]=a[6]*e;b[7]=a[7]*e;b[8]=a[8]*c;b[9]=a[9]*c;b[10]=a[10]*c;b[11]=a[11]*c;b[12]=a[12];b[13]=a[13];b[14]=a[14];b[15]=a[15];return b},
	inverse:function(c,a){a||(a=c);var d=c[0],e=c[1],f=c[2],g=c[3],h=c[4],i=c[5],j=c[6],k=c[7],l=c[8],m=c[9],n=c[10],o=c[11],p=c[12],q=c[13],r=c[14],s=c[15],t=d*i-e*h,u=d*j-f*h,v=d*k-g*h,w=e*j-f*i,x=e*k-g*i,y=f*k-g*j,z=l*q-m*p,A=l*r-n*p,B=l*s-o*p,C=m*r-n*q,D=m*s-o*q,E=n*s-o*r,b=t*E-u*D+v*C+w*B-x*A+y*z;if(!b)return null;b=1/b;a[0]=(i*E-j*D+k*C)*b;a[1]=(-e*E+f*D-g*C)*b;a[2]=(q*y-r*x+s*w)*b;a[3]=(-m*y+n*x-o*w)*b;a[4]=(-h*E+j*B-k*A)*b;a[5]=(d*E-f*B+g*A)*b;a[6]=(-p*y+r*v-s*u)*b;a[7]=(l*y-n*v+o*u)*b;a[8]=(h*D-i*B+k*z)*b;a[9]=(-d*D+e*B-g*z)*b;a[10]=(p*x-q*v+s*t)*b;a[11]=(-l*x+m*v-o*t)*b;a[12]=(-h*C+i*A-j*z)*b;a[13]=(d*C-e*A+f*z)*b;a[14]=(-p*w+q*u-r*t)*b;a[15]=(l*w-m*u+n*t)*b;return a},
	multiply:function(a,b,c){c||(c=a);var d=a[0],e=a[1],f=a[2],g=a[3],h=a[4],i=a[5],j=a[6],k=a[7],l=a[8],m=a[9],n=a[10],o=a[11],p=a[12],q=a[13],r=a[14],a=a[15],s=b[0],t=b[1],u=b[2],v=b[3],w=b[4],x=b[5],y=b[6],z=b[7],A=b[8],B=b[9],C=b[10],D=b[11],E=b[12],F=b[13],G=b[14],b=b[15];c[0]=s*d+t*h+u*l+v*p;c[1]=s*e+t*i+u*m+v*q;c[2]=s*f+t*j+u*n+v*r;c[3]=s*g+t*k+u*o+v*a;c[4]=w*d+x*h+y*l+z*p;c[5]=w*e+x*i+y*m+z*q;c[6]=w*f+x*j+y*n+z*r;c[7]=w*g+x*k+y*o+z*a;c[8]=A*d+B*h+C*l+D*p;c[9]=A*e+B*i+C*m+D*q;c[10]=A*f+B*j+C*n+D*r;c[11]=A*g+B*k+C*o+D*a;c[12]=E*d+F*h+G*l+b*p;c[13]=E*e+F*i+G*m+b*q;c[14]=E*f+F*j+G*n+b*r;c[15]=E*g+F*k+G*o+b*a;return c}
}
`