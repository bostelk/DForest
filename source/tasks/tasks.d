module tasks;

import std.stdio : writeln, writefln;
import std.file : read;
import std.zip;
import std.algorithm;
import libpng.png;
import std.parallelism;
import std.datetime.stopwatch : benchmark, StopWatch;

struct rgba_image {
    string name;
    int width;
    int height;
    ubyte[] data;
}

rgba_image[] read_rgba_images_from_archive(string filename) {
    // read a zip file into memory
    ZipArchive zip = new ZipArchive(read(filename));
    writefln("searching archive '%s'.", filename);

    ArchiveMember[] members = find_members_in_archive(zip, filename);
    writefln("found %s images in archive.", members.length);

    rgba_image[] images;
    foreach (member; parallel(members))
    {
        //writefln("read image from member: %s", member.name);
        rgba_image image = read_rgba_image_from_archive_member(zip, member);
        //writefln("width x height: %s x %s.", image.width, image.height);
        images ~= image;
    }
    return images;
}

ArchiveMember[] find_members_in_archive(ZipArchive zip, string filename) {
    ArchiveMember[] members;

    foreach (name, am; zip.directory)
    {
        if (!name.endsWith("png")) {
            continue;
        }

        // print some data about each member
        writefln("%10s  %08x  %s", am.expandedSize, am.crc32, name);
        assert(am.expandedData.length == 0);

        members ~= am;
    }
    return members;
}

rgba_image read_rgba_image_from_archive_member(ZipArchive zip, ArchiveMember member)
{
    rgba_image image_1;

    // decompress the archive member
    zip.expand(member);

    assert(member.expandedData.length == member.expandedSize);

    png_image image;
    image.version_ = PNG_IMAGE_VERSION;

    void* memory = &member.expandedData[0];
    ulong size = member.expandedData.length;

    int ret = png_image_begin_read_from_memory(&image, memory, size);
    if (ret==1)
    {
        assert(image.format == PNG_FORMAT_RGBA);
        assert((image.format & PNG_FORMAT_FLAG_COLORMAP) == 0);

        ubyte[] buffer = new ubyte[PNG_IMAGE_SIZE(&image)];

        // no background to remove or color map.
        int row_stride = 0;
        png_color* background = null;
        void* colormap = null;

        ret = png_image_finish_read(&image, background, &buffer[0], row_stride, colormap);
        if (ret == 1) {
            image_1.name = member.name;
            image_1.width = image.width;
            image_1.height = image.height;
            image_1.data = buffer;
        }

        png_image_free(&image);
    }

    return image_1;
}

