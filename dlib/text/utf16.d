/*
Copyright (c) 2016-2020 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

/**
 * Copyright: Timur Gafarov 2016-2020.
 * License: $(LINK2 boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Timur Gafarov, Roman Chistokhodov
 */
module dlib.text.utf16;

import core.stdc.stdio;
import dlib.core.memory;
import dlib.container.array;
import dlib.text.utf8;
import dlib.text.utils;
import dlib.text.common;

enum ushort UTF16_HI_SURROGATE = 0xD800;
enum ushort UTF16_LO_SURROGATE = 0xDC00;
enum ushort UTF16_BOM_LE = 0xfeff;
enum ushort UTF16_BOM_BE = 0xfffe;

/**
 * UTF-16 LE decoder
 */
struct UTF16Decoder
{
    // TODO: byte order
    
    size_t index = 0;
    int character = 0;
    string input;

    this(string str)
    {
        index = 0;
        character = 0;
        input = str;
    }

    int decodeNext()
    {
        if (index >= input.length)
            return index == input.length ? DECODE_END : DECODE_ERROR;
        character++;
        wchar c = *cast(wchar*)(&input[index]);
        index += 2;
        return c;
    }

    bool eos()
    {
        return (index >= input.length);
    }

    auto byDChar()
    {
        static struct ByDchar
        {
            private:
            UTF16Decoder _decoder;
            dchar _lastRead;

            public:
            this(UTF16Decoder decoder) {
                _decoder = decoder;
                _lastRead = cast(dchar)_decoder.decodeNext();
            }

            bool empty() {
                return _lastRead == DECODE_END || _lastRead == DECODE_ERROR;
            }

            dchar front() {
                return _lastRead;
            }

            void popFront() {
                _lastRead = cast(dchar)_decoder.decodeNext();
            }

            auto save() {
                return this;
            }
        }

        return ByDchar(this);
    }
}

/**
 * Encodes a Unicode code point to UTF-16 LE into user-provided buffer.
 * Returns number of bytes written, or 0 at error.
 */
struct UTF16Encoder
{
    size_t encode(uint ch, char[] buffer)
    {
        wchar[] wbuffer = cast(wchar[])buffer;
        if (ch > 0xFFFF)
        {
            wchar x = cast(wchar)ch;
            wchar vh = cast(wchar)(UTF16_HI_SURROGATE | ((((ch >> 16) & ((1 << 5) - 1)) - 1) << 6) | (x >> 10));
            wchar vl = cast(wchar)(UTF16_LO_SURROGATE | (x & ((1 << 10) - 1)));
            wbuffer[0] = vh;
            wbuffer[1] = vl;
            return 4;
        }
        else
        {
            wbuffer[0] = cast(wchar)ch;
            return 2;
        }
    }
}

/**
 * Converts UTF8 to UTF8
 * Will be deprecated soon, use transcode!(UTF8Decoder, UTF16Encoder) instead
 */
wchar[] convertUTF8toUTF16(string s, bool nullTerm = false)
{
    DynamicArray!wchar array;
    wchar[] output;

    UTF8Decoder dec = UTF8Decoder(s);

    while(!dec.eos)
    {
        int code = dec.decodeNext();

        if (code == UTF8_ERROR)
        {
            array.free();
            return output;
        }

        dchar ch = cast(dchar)code;

        if (ch > 0xFFFF)
        {
            // Split ch up into a surrogate pair as it is over 16 bits long.
            wchar x = cast(wchar)ch;
            auto vh = UTF16_HI_SURROGATE | ((((ch >> 16) & ((1 << 5) - 1)) - 1) << 6) | (x >> 10);
            auto vl = UTF16_LO_SURROGATE | (x & ((1 << 10) - 1));
            array.append(cast(wchar)vh);
            array.append(cast(wchar)vl);
        }
        /*
        else if (ch >= 0xD800 && ch <= 0xDFFF)
        {
            // Between possible UTF-16 surrogates (invalid!)
            array[pos++] = UTF_REPLACEMENT_CHARACTER;
        }
        */
        else
        {
            array.append(cast(wchar)ch);
        }
    }

    if (nullTerm)
    {
        array.append(0);
    }

    output = copy(array.data);
    array.free();
    return output;
}

/**
 * Converts UTF16 zero-terminated string to UTF8
 */
char[] convertUTF16ztoUTF8(wchar* s, bool nullTerm = false)
{
    DynamicArray!char array;
    char[] output;
    wchar* utf16 = s;

    wchar utf16char;
    do
    {
        utf16char = *utf16;
        utf16++;

        if (utf16char)
        {
            if (utf16char < 0x80)
            {
                array.append((utf16char >> 0 & 0x7F) | 0x00);
            }
            else if (utf16char < 0x0800)
            {
                array.append((utf16char >> 6 & 0x1F) | 0xC0);
                array.append((utf16char >> 0 & 0x3F) | 0x80);
            }
            else if (utf16char < 0x010000)
            {
                array.append((utf16char >> 12 & 0x0F) | 0xE0);
                array.append((utf16char >> 6 & 0x3F) | 0x80);
                array.append((utf16char >> 0 & 0x3F) | 0x80);
            }
            else if (utf16char < 0x110000)
            {
                array.append((utf16char >> 18 & 0x07) | 0xF0);
                array.append((utf16char >> 12 & 0x3F) | 0x80);
                array.append((utf16char >> 6 & 0x3F) | 0x80);
                array.append((utf16char >> 0 & 0x3F) | 0x80);
            }
        }
    }
    while (utf16char);

    if (nullTerm)
    {
        array.append(0);
    }

    output = copy(array.data);
    array.free();
    return output;
}
