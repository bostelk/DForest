import std.stdio : writeln, writefln;
import std.parallelism;
import std.datetime.stopwatch : benchmark, StopWatch;
import std.format;
import std.random;
import std.algorithm;
import core.stdc.math; //tanf

import derelict.glfw3.glfw3;
import bindbc.opengl;
import gl3n.linalg;

import tasks;
import noise;

float[] vertices =
[
    //  Position      Color             Texcoords
    -0.5,  0.5, 0.0, 0.5, 0.0, 0.0, 0.0, // Top-left
     0.5,  0.5, 0.0, 0.0, 1.0, 1.0, 0.0, // Top-right
     0.5, -0.5, 0.0, 0.0, 1.0, 1.0, 1.0, // Bottom-right
    -0.5, -0.5, 1.0, 1.0, 1.0, 0.0, 1.0  // Bottom-left
];

static const char* vertex_shader_text = "
#version 330
uniform mat4 MVP;
attribute vec2 vPos;
uniform vec2 vOffset;
attribute vec3 vCol;
attribute vec2 vTex;
varying vec3 color;
varying vec2 texcoord;
void main()
{
    gl_Position = MVP * vec4(vPos+vOffset, 0.0, 1.0);
    color = vCol;
    texcoord = vTex;
}";

static const char* fragment_shader_text =
"#version 330
varying vec3 color;
varying vec2 texcoord;
uniform sampler2D tex;
void main()
{
    vec4 col = texture2D(tex, texcoord);
    gl_FragColor = col;//vec4(col.aaa, 1.0);
}";


static void mat4x4_ortho(mat4 M, float l, float r, float b, float t, float n, float f)
{
    M[0][0] = 2./(r-l);
    M[0][1] = M[0][2] = M[0][3] = 0.;

    M[1][1] = 2./(t-b);
    M[1][0] = M[1][2] = M[1][3] = 0.;

    M[2][2] = -2./(f-n);
    M[2][0] = M[2][1] = M[2][3] = 0.;

    M[3][0] = -(r+l)/(r-l);
    M[3][1] = -(t+b)/(t-b);
    M[3][2] = -(f+n)/(f-n);
    M[3][3] = 1.;
}

void mat4x4_perspective(mat4 m, float y_fov, float aspect, float n, float f)
{
    /* NOTE: Degrees are an unhandy unit to work with.
     * linmath.h uses radians for everything! */
    float a = 1. / tanf(y_fov / 2.);

    m[0][0] = a / aspect;
    m[0][1] = 0.;
    m[0][2] = 0.;
    m[0][3] = 0.;

    m[1][0] = 0.;
    m[1][1] = a;
    m[1][2] = 0.;
    m[1][3] = 0.;

    m[2][0] = 0.;
    m[2][1] = 0.;
    m[2][2] = -((f + n) / (f - n));
    m[2][3] = -1.;

    m[3][0] = 0.;
    m[3][1] = 0.;
    m[3][2] = -((2. * f * n) / (f - n));
    m[3][3] = 0.;
}

void printShaderInfoLog(GLuint shader) {
    GLint maxLength = 0;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &maxLength);
    assert(glGetError() == GL_NO_ERROR);

    if (maxLength > 0) {
    char[] info = new char[maxLength];
    glGetShaderInfoLog(shader, maxLength, &maxLength, &info[0]);
    assert(glGetError() == GL_NO_ERROR);
    writeln(info);
    }
}

void printProgramInfoLog(GLuint program) {
    GLint maxLength = 0;
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &maxLength);
    assert(glGetError() == GL_NO_ERROR);

    if (maxLength > 0) {
    char[] info = new char[maxLength];
    glGetProgramInfoLog(program, maxLength, &maxLength, &info[0]);
    assert(glGetError() == GL_NO_ERROR);
    writeln(info);
    }
}

int main()
{
    writefln("There are %s cores on this system.", totalCPUs);

    DerelictGLFW3.load();
       if (!glfwInit()) {
        //exit(-1);
       }

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);

     const GLFWvidmode * mode = glfwGetVideoMode(glfwGetPrimaryMonitor());

    int window_width = mode.width;
    int window_height = mode.height;

    //window_width = 800;
    //window_height = 640;
    //window_width = 1920;
    //window_height = 1080;

    auto window = glfwCreateWindow(window_width, window_height, "Forest", null, null);
    if (!window)
    {
        glfwTerminate();
        //exit(EXIT_FAILURE);
    }

    //glfwSetKeyCallback(window, key_callback); skip

    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);

// Create OpenGL context
//...
// Load supported OpenGL version + supported extensions
GLSupport retVal = loadOpenGL();
if(retVal == GLSupport.gl41) {
    // configure renderer for OpenGL 4.1
    writeln("test");
}
else if(retVal == GLSupport.gl33) {
    // configure renderer for OpenGL 3.3
    writeln("opengl 33");
}
else {
    // Error
    writeln(retVal);//"test2");
}

    GLuint vertex_shader, fragment_shader, shaderProgram;
    GLint mvp_location, vpos_location, vcol_location, vtex_location, voffset_location;

    GLuint vao;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    assert(glGetError() == GL_NO_ERROR);

    // Create a Vertex Buffer Object and copy the vertex data to it
    GLuint vbo;
    glGenBuffers(1, &vbo);
    assert(glGetError() == GL_NO_ERROR);

    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    writefln("vertices:%s",vertices.sizeof);
    glBufferData(GL_ARRAY_BUFFER, vertices.length * GLfloat.sizeof, &vertices[0], GL_STATIC_DRAW);
    assert(glGetError() == GL_NO_ERROR);

    // Create an element array
    GLuint ebo;
    glGenBuffers(1, &ebo);
    assert(glGetError() == GL_NO_ERROR);

    GLuint[] elements = [
        0, 1, 2,
        2, 3, 0
    ];

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, elements.length * GLuint.sizeof, &elements[0], GL_STATIC_DRAW);
    assert(glGetError() == GL_NO_ERROR);

    vertex_shader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertex_shader, 1, &vertex_shader_text, null);
    glCompileShader(vertex_shader);

    printShaderInfoLog(vertex_shader);

    fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragment_shader, 1, &fragment_shader_text, null);
    glCompileShader(fragment_shader);

    printShaderInfoLog(fragment_shader);

    shaderProgram = glCreateProgram();
    glAttachShader(shaderProgram, vertex_shader);
    glAttachShader(shaderProgram, fragment_shader);
    glLinkProgram(shaderProgram);

    printProgramInfoLog(shaderProgram);
    assert(glGetError() == GL_NO_ERROR);

    mvp_location = glGetUniformLocation(shaderProgram, "MVP");
    voffset_location = glGetUniformLocation(shaderProgram, "vOffset");

    vpos_location = glGetAttribLocation(shaderProgram, "vPos");
    glEnableVertexAttribArray(vpos_location);
    glVertexAttribPointer(vpos_location, 2, GL_FLOAT, GL_FALSE,
                          7 * GLfloat.sizeof, cast(void*) 0);

    vcol_location = glGetAttribLocation(shaderProgram, "vCol");
    glEnableVertexAttribArray(vcol_location);
    glVertexAttribPointer(vcol_location, 3, GL_FLOAT, GL_FALSE,
                          7 * GLfloat.sizeof, cast(void*) (GLfloat.sizeof * 2));

    vtex_location = glGetAttribLocation(shaderProgram, "vTex");
    glEnableVertexAttribArray(vtex_location);
    glVertexAttribPointer(vtex_location, 2, GL_FLOAT, GL_FALSE,
                          7 * GLfloat.sizeof, cast(void*) (GLfloat.sizeof * 5));
    assert(glGetError() == GL_NO_ERROR);

    rgba_image[] images;
    {
        auto sw = StopWatch();

        sw.start();
        string filename = "input/Animated Swietenia.zip";
        auto read_images_task = task!read_rgba_images_from_archive(filename);
        taskPool.put(read_images_task);
        images = read_images_task.yieldForce;
        sw.stop();

        long msecs = sw.peek.total!"msecs";
        writefln("finished in %s msecs.", msecs);
    }

    GLuint[] textures;
    textures.length = images.length;
    glGenTextures(cast(int)textures.length, &textures[0]);

    GLuint[string] nameToTextureId;
    int[string] nameToImageId;

    for(int i =0; i < images.length; i++) {
        nameToTextureId[images[i].name] = textures[i];
        nameToImageId[images[i].name] = i;
        glActiveTexture(GL_TEXTURE0);// + i);
        glBindTexture(GL_TEXTURE_2D, textures[i]);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, images[i].width, images[i].height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, &images[i].data[0]);
        assert(glGetError() == GL_NO_ERROR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    }

    struct animState {
        float elapsed = 0;
        int frame = 0;
        int step = 1;
        int imageId = 0;
        GLuint texId = 0;
    }
    struct transform {
        float x = 0;
        float y = 0;
        float scaleX = 1;
        float scaleY = 1;
    }

    auto rnd = Random(unpredictableSeed);

    int numTrees = 100;

    transform[] transforms;
    transforms.length = numTrees;

    // blue noise
    initSamplers();
    /// some kind of pow of 2.
    Point[] bSamples = ldbnSTEP(cast(uint)2048);

    for(int i = 0; i < transforms.length;i++) {
        if (false) {
        //transforms[i].x = uniform(cast(float)window_width*-0.5, cast(float)window_width*0.5, rnd);
        //transforms[i].y = uniform(cast(float)window_width*-0.5, cast(float)window_height*0.5, rnd);
        } else {
        int sampleIndex= cast(int)uniform(0, bSamples.length);
        Point sample = bSamples[sampleIndex];

        // remap 0,1 to range dist.
        float rangeDist = 1.5 * 3;
        float range = rangeDist * 2;

        transforms[i].x = (sample[0]*range-rangeDist);//*cast(float)window_width;
        transforms[i].y = (sample[1]*range-rangeDist);//*cast(float)window_height;
        }
    }

        transforms[0].x = -1.5;//*cast(float)window_width;
        transforms[0].y = -1.5;//*cast(float)window_height;

        transforms[1].x = 1.5;//*cast(float)window_width;
        transforms[1].y = -1.5;//*cast(float)window_height;

        transforms[2].x = -1.5;//*cast(float)window_width;
        transforms[2].y = 1.5;//*cast(float)window_height;

        transforms[3].x = 1.5;//*cast(float)window_width;
        transforms[3].y = 1.5;//*cast(float)window_height;

    // painter order.
    sort!((a,b)=>a.y > b.y)(transforms);

    animState[] animStates;
    animStates.length = numTrees;

    for(int i = 0; i < animStates.length;i++) {
        animStates[i].frame = uniform(0, cast(int)textures.length - 1, rnd);
    }

    GLint texLocation = glGetUniformLocation(fragment_shader, "tex");
    glGetError();
    //assert(glGetError() == GL_NO_ERROR); //uniform not active; optimized away?

    float time = glfwGetTime();
    float elapsed = 0;
    int frame = 0;

    while (!glfwWindowShouldClose(window))
    {
        float now = glfwGetTime();
        float dt = now - time;
        time = now;
        elapsed += dt;
        frame ++;
        if (frame > 2000) frame =0; //wrap for noise

        //writeln(dt);

        int width, height;
        float ratio;

        glfwGetFramebufferSize(window, &width, &height);

        ratio = width / cast(float) height;
        float widthToPixels = 1/cast(float)width;
        float heightToPixels = 1/cast(float)height;

        glViewport(0, 0, width, height);
        glClearColor(0.0, 0.0, 0.0, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        glCullFace(GL_FRONT); //GL_BACK
        glEnable (GL_BLEND);
        glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glUseProgram(shaderProgram);

        for(int i = 0; i < animStates.length; i++) {

            mat4 m, p, mvp;

            // normalize
            rgba_image image = images[animStates[i].imageId];
            float sx = cast(float)image.width/cast(float)width;
            float sy = cast(float)image.height/cast(float)height;

            // voffset is replacing translate because it skews the image.
            m = mat4.identity.translate(0, 0, 0).scale(sx, sy, 1.0);
            //writeln(m);

            p = p.identity();
            //mat4x4_perspective(p, 1.57, ratio, 1,10);
            mat4x4_ortho(p, -ratio, ratio, -1., 1., 1., -1.);
            mvp = p * m;

            assert(glGetError() == GL_NO_ERROR);
            glUniformMatrix4fv(mvp_location, 1, GL_FALSE, cast(const GLfloat*) &mvp[0]);
            assert(glGetError() == GL_NO_ERROR);
            glUniform1i(texLocation, 0);
            // width and height to pixels are not good..
            glUniform2f(voffset_location, transforms[i].x * 1, transforms[i].y * 1);
            glGetError();
            //assert(glGetError() == GL_NO_ERROR); //uniform not active; optimized away?

            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, textures[animStates[i].texId]);
            assert(glGetError() == GL_NO_ERROR);

            glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, cast(void*) 0);
            assert(glGetError() == GL_NO_ERROR);
        }

        glfwSwapBuffers(window);
        glfwPollEvents();

        int state = glfwGetKey(window, GLFW_KEY_R);
        if (state == GLFW_PRESS)
        {
            writeln("generate new forest");
            for(int i = 0; i < transforms.length;i++) {
                int sampleIndex= cast(int)uniform(0, bSamples.length);
                Point sample = bSamples[sampleIndex];

                // remap 0,1 to range dist.
                float rangeDist = 1.5 * 3;
                float range = rangeDist * 2;

                transforms[i].x = (sample[0]*range-rangeDist);//*cast(float)window_width;
                transforms[i].y = (sample[1]*range-rangeDist);//*cast(float)window_height;
            }

            // painter order.
            sort!((a,b)=>a.y > b.y)(transforms);
        }

        for(int i = 0; i < animStates.length; i++) {
            animStates[i].elapsed += dt;
            if (animStates[i].elapsed > (1.2 * 1/30)) {
                string filename = format("Animated Swietenia/_test_tree-animation_%04d.png", animStates[i].frame);

                if (
                        (filename in nameToImageId)&&
                        (filename in nameToTextureId)) {

                    animStates[i].imageId = nameToImageId[filename];
                    animStates[i].texId = nameToTextureId[filename] - 1;

                    assert(images[animStates[i].imageId].name==filename);
                } else {
                    writefln("failed to find:%s", filename);
                }

                if (animStates[i].step > 0) {
                    if (animStates[i].frame == textures.length - 1) {
                        animStates[i].step = -1;
                    }
                }
                else {
                    if (animStates[i].frame == 0) {
                        animStates[i].step = 1;
                    }
                }

                animStates[i].frame += animStates[i].step;
                animStates[i].elapsed = 0;
            }
        }
    }

    glfwDestroyWindow(window);

    glfwTerminate();

    return 0;
}
