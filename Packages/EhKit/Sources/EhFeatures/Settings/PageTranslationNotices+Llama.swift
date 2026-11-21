import Foundation

// The notices of the code llama.cpp's library contains, each the licence's own text as its
// upstream has it at the commit llama.cpp b12359 vendors. What is here and why is decided
// from the shipped framework: its symbols show each of these, and none of nlohmann/json,
// cpp-httplib or subprocess.h, which that build leaves out. llama.cpp's Unicode tables are
// generated from the Unicode Character Database: its general tables from `UnicodeData.txt`
// of Unicode 15.1.0 (what they hold matches 15.1.0, not 16.0.0), its normalization tables
// from Unicode 16.0.0, as their header says.
nonisolated extension PageTranslationNotice {
    /// In the order the licences screen lists them, after llama.cpp.
    public static let llamaParts: [PageTranslationNotice] = [
        .miniaudio,
        .rotateBits,
        .sha1,
        .sha256,
        .stbImage,
        .tinyBLAS,
        .unicode,
        .xxHash,
        .yarn,
    ]

    static let miniaudio = PageTranslationNotice(
        name: "miniaudio v0.11.26",
        source: URL(string: "https://github.com/mackron/miniaudio/blob/877ea4a7c2601c7b0f2a44e83dfac42e6470fea6/miniaudio.h"),
        text: """
        This software is available as a choice of the following licenses. Choose
        whichever you prefer.

        ===============================================================================
        ALTERNATIVE 1 - Public Domain (www.unlicense.org)
        ===============================================================================
        This is free and unencumbered software released into the public domain.

        Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
        software, either in source code form or as a compiled binary, for any purpose,
        commercial or non-commercial, and by any means.

        In jurisdictions that recognize copyright laws, the author or authors of this
        software dedicate any and all copyright interest in the software to the public
        domain. We make this dedication for the benefit of the public at large and to
        the detriment of our heirs and successors. We intend this dedication to be an
        overt act of relinquishment in perpetuity of all present and future rights to
        this software under copyright law.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
        ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
        WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

        For more information, please refer to <http://unlicense.org/>

        ===============================================================================
        ALTERNATIVE 2 - MIT No Attribution
        ===============================================================================
        Copyright 2026 David Reid

        Permission is hereby granted, free of charge, to any person obtaining a copy of
        this software and associated documentation files (the "Software"), to deal in
        the Software without restriction, including without limitation the rights to
        use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
        of the Software, and to permit persons to whom the Software is furnished to do
        so.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    )

    static let rotateBits = PageTranslationNotice(
        name: "rotate-bits.h",
        source: URL(string: "https://github.com/jb55/rotate-bits.h/blob/27e784942f67db44abf2115c6638e735b579acd1/LICENSE.md"),
        text: """
        MIT License

        Copyright (c) 2021 William Casarin <jb55@jb55.com>

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    )

    static let sha1 = PageTranslationNotice(
        name: "SHA-1 in C",
        source: URL(string: "https://github.com/clibs/sha1/blob/e1e2536fcf6a8f9703be8c85d58724b408552287/sha1.c"),
        text: """
        SHA-1 in C
        By Steve Reid <steve@edmweb.com>
        100% Public Domain
        """
    )

    static let sha256 = PageTranslationNotice(
        name: "sha256.c",
        source: URL(string: "https://github.com/jb55/sha256.c/blob/5e637272c13f200872d55ff579f7e2ab6c3f252f/LICENSE"),
        text: """
        2010-06-11 : Igor Pavlov : Public domain
        """
    )

    static let stbImage = PageTranslationNotice(
        name: "stb_image v2.30",
        source: URL(string: "https://github.com/nothings/stb/blob/013ac3beddff3dbffafd5177e7972067cd2b5083/stb_image.h"),
        text: """
        ------------------------------------------------------------------------------
        This software is available under 2 licenses -- choose whichever you prefer.
        ------------------------------------------------------------------------------
        ALTERNATIVE A - MIT License
        Copyright (c) 2017 Sean Barrett
        Permission is hereby granted, free of charge, to any person obtaining a copy of
        this software and associated documentation files (the "Software"), to deal in
        the Software without restriction, including without limitation the rights to
        use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
        of the Software, and to permit persons to whom the Software is furnished to do
        so, subject to the following conditions:
        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.
        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        ------------------------------------------------------------------------------
        ALTERNATIVE B - Public Domain (www.unlicense.org)
        This is free and unencumbered software released into the public domain.
        Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
        software, either in source code form or as a compiled binary, for any purpose,
        commercial or non-commercial, and by any means.
        In jurisdictions that recognize copyright laws, the author or authors of this
        software dedicate any and all copyright interest in the software to the public
        domain. We make this dedication for the benefit of the public at large and to
        the detriment of our heirs and successors. We intend this dedication to be an
        overt act of relinquishment in perpetuity of all present and future rights to
        this software under copyright law.
        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
        ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
        WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        ------------------------------------------------------------------------------
        """
    )

    static let tinyBLAS = PageTranslationNotice(
        name: "tinyBLAS (llamafile)",
        source: URL(string: "https://github.com/ggml-org/llama.cpp/blob/b1b770d90d94cad9e9ea5b993bdbc383a522fb28/ggml/src/ggml-cpu/llamafile/sgemm.cpp"),
        text: """
        Copyright 2024 Mozilla Foundation

        Permission is hereby granted, free of charge, to any person obtaining
        a copy of this software and associated documentation files (the
        "Software"), to deal in the Software without restriction, including
        without limitation the rights to use, copy, modify, merge, publish,
        distribute, sublicense, and/or sell copies of the Software, and to
        permit persons to whom the Software is furnished to do so, subject to
        the following conditions:

        The above copyright notice and this permission notice shall be
        included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
        EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
        NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
        BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
        ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
        CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    )

    static let unicode = PageTranslationNotice(
        name: "Unicode Character Database 15.1.0 and 16.0.0",
        source: URL(string: "https://www.unicode.org/Public/15.1.0/ucd/UnicodeData.txt"),
        text: """
        UNICODE LICENSE V3

        COPYRIGHT AND PERMISSION NOTICE

        Copyright © 1991-2026 Unicode, Inc.

        NOTICE TO USER: Carefully read the following legal agreement. BY
        DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
        SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
        TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
        DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

        Permission is hereby granted, free of charge, to any person obtaining a
        copy of data files and any associated documentation (the "Data Files") or
        software and any associated documentation (the "Software") to deal in the
        Data Files or Software without restriction, including without limitation
        the rights to use, copy, modify, merge, publish, distribute, and/or sell
        copies of the Data Files or Software, and to permit persons to whom the
        Data Files or Software are furnished to do so, provided that either (a)
        this copyright and permission notice appear with all copies of the Data
        Files or Software, or (b) this copyright and permission notice appear in
        associated Documentation.

        THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
        KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
        MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
        THIRD PARTY RIGHTS.

        IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
        BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
        OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
        WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
        ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
        FILES OR SOFTWARE.

        Except as contained in this notice, the name of a copyright holder shall
        not be used in advertising or otherwise to promote the sale, use or other
        dealings in these Data Files or Software without prior written
        authorization of the copyright holder.
        """
    )

    static let xxHash = PageTranslationNotice(
        name: "xxHash v0.8.3",
        source: URL(string: "https://github.com/Cyan4973/xxHash/blob/9f465f1ea932d6ad9a26cd77496311ffa544cd68/LICENSE"),
        text: """
        xxHash Library
        Copyright (c) 2012-2021 Yann Collet
        All rights reserved.

        BSD 2-Clause License (https://www.opensource.org/licenses/bsd-license.php)

        Redistribution and use in source and binary forms, with or without modification,
        are permitted provided that the following conditions are met:

        * Redistributions of source code must retain the above copyright notice, this
          list of conditions and the following disclaimer.

        * Redistributions in binary form must reproduce the above copyright notice, this
          list of conditions and the following disclaimer in the documentation and/or
          other materials provided with the distribution.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
        ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
        WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
        DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
        ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
        (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
        LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
        ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
        (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
        SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
        """
    )

    static let yarn = PageTranslationNotice(
        name: "YaRN",
        source: URL(string: "https://github.com/jquesnelle/yarn/blob/995db5b575e75230b3384d658f8b944c9662f775/LICENSE"),
        text: """
        MIT License

        Copyright (c) 2023 Jeffrey Quesnelle and Bowen Peng

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    )
}
