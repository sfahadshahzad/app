#!/bin/bash -ex

source build/lib/versions.sh
source build/lib/functions.sh

if [ "$BUILD_OS" == "windows32" ] || [ "$BUILD_OS" == "windows64" ]; then
    curl -s https://raw.githubusercontent.com/mikkeloscar/arch-travis/master/arch-travis.sh | bash
    exit 0
fi

# Start build
#-----------------------------------------------------------------------------
sl_prepare

sl_extra_lflags="-L ../opus -L ../my_include "
sl_extra_lflags_standalone="$sl_extra_lflags -L ../openssl "

if [ "$TRAVIS_OS_NAME" == "linux" ]; then
    sl_extra_modules="alsa jack rtaudio"
else
    export MACOSX_DEPLOYMENT_TARGET=10.6
    sl_extra_lflags+="-L ../openssl "
    sl_extra_lflags+="-framework SystemConfiguration "
    sl_extra_lflags+="-framework CoreFoundation"
    sl_extra_modules="audiounit rtaudio"
    sed_opt="-i ''"
fi


# Build RtAudio
#-----------------------------------------------------------------------------
if [ ! -d rtaudio-${rtaudio} ]; then
    sl_get_rtaudio
    pushd rtaudio-${rtaudio}
    if [ "$TRAVIS_OS_NAME" == "linux" ]; then
        ./autogen.sh
    else
        export CPPFLAGS="-Wno-deprecated"
        sudo mkdir -p /usr/local/Library/ENV/4.3
        sudo ln -s $(which sed) /usr/local/Library/ENV/4.3/sed
        ./autogen.sh --with-core
    fi
    make
    unset CPPFLAGS
    cp -a .libs/librtaudio.a ../my_include/
    popd
fi


# Build FLAC
#-----------------------------------------------------------------------------
if [ ! -d flac-${flac} ]; then
    sl_get_flac

    cd flac
    ./configure --disable-ogg --enable-static
    make
    cp -a include/FLAC ../my_include/
    cp -a include/share ../my_include/
    cp -a src/libFLAC/.libs/libFLAC.a ../my_include/
    cd ..
fi


# Build openssl
#-----------------------------------------------------------------------------
if [ ! -d openssl-${openssl} ]; then
    sl_get_openssl
    cd openssl
    ./config no-shared
    make build_libs
    cp -a include/openssl ../my_include/
    cd ..
fi


# Build opus
#-----------------------------------------------------------------------------
if [ ! -d opus-$opus ]; then
    wget "https://archive.mozilla.org/pub/opus/opus-${opus}.tar.gz"
    tar -xzf opus-${opus}.tar.gz
    cd opus-$opus; ./configure --with-pic; make; cd ..
    mkdir opus; cp opus-$opus/.libs/libopus.a opus/
    mkdir -p my_include/opus
    cp opus-$opus/include/*.h my_include/opus/ 
fi


# Build libre
#-----------------------------------------------------------------------------
if [ ! -d re-$re ]; then
    sl_get_libre

    # WARNING build releases with RELEASE=1, because otherwise its MEM Debug
    # statements are not THREAD SAFE! on every platform, especilly windows.
    make -C re $debug USE_OPENSSL=1 EXTRA_CFLAGS="-I ../my_include/" libre.a
    mkdir -p my_include/re
    cp -a re/include/* my_include/re/
fi


# Build librem
#-----------------------------------------------------------------------------
if [ ! -d rem-$rem ]; then
    sl_get_librem
    cd rem
    make $debug librem.a 
    cd ..
fi


# Build baresip with studio link addons
#-----------------------------------------------------------------------------
if [ ! -d baresip-$baresip ]; then
    sl_get_baresip

    pushd baresip-$baresip
    # Standalone
    make $debug LIBRE_SO=../re LIBREM_PATH=../rem STATIC=1 \
        MODULES="opus stdio ice g711 turn stun uuid auloop webapp $sl_extra_modules" \
        EXTRA_CFLAGS="-I ../my_include" \
        EXTRA_LFLAGS="$sl_extra_lflags_standalone"

    cp -a baresip ../studio-link-standalone

    # libbaresip.a without effect plugin
    make $debug LIBRE_SO=../re LIBREM_PATH=../rem STATIC=1 \
        MODULES="opus stdio ice g711 turn stun uuid auloop webapp $sl_extra_modules" \
        EXTRA_CFLAGS="-I ../my_include" \
        EXTRA_LFLAGS="$sl_extra_lflags" libbaresip.a
    cp -a libbaresip.a ../my_include/libbaresip_standalone.a

    # Effectonair Plugin
    make clean
    make $debug LIBRE_SO=../re LIBREM_PATH=../rem STATIC=1 \
        MODULES="opus stdio ice g711 turn stun uuid auloop apponair effectonair" \
        EXTRA_CFLAGS="-I ../my_include -DSLIVE" \
        EXTRA_LFLAGS="$sl_extra_lflags" libbaresip.a
    cp -a libbaresip.a ../my_include/libbaresip_onair.a

    # Effect Plugin
    make clean
    make $debug LIBRE_SO=../re LIBREM_PATH=../rem STATIC=1 \
        MODULES="opus stdio ice g711 turn stun uuid auloop webapp effect" \
        EXTRA_CFLAGS="-I ../my_include -DSLPLUGIN" \
        EXTRA_LFLAGS="$sl_extra_lflags" libbaresip.a

    popd
fi


# Build overlay-lv2 plugin (linux only)
#-----------------------------------------------------------------------------
if [ "$TRAVIS_OS_NAME" == "linux" ]; then
    if [ ! -d overlay-lv2 ]; then
        git clone $github_org/overlay-lv2.git overlay-lv2
        cd overlay-lv2; ./build.sh; cd ..
    fi
fi


# Build overlay-onair-lv2 plugin (linux only)
#-----------------------------------------------------------------------------
if [ "$TRAVIS_OS_NAME" == "linux" ]; then
    if [ ! -d overlay-onair-lv2 ]; then
        git clone $github_org/overlay-onair-lv2.git overlay-onair-lv2
        cd overlay-onair-lv2; ./build.sh; cd ..
    fi
fi


# Build overlay-audio-unit plugin (osx only)
#-----------------------------------------------------------------------------
if [ "$TRAVIS_OS_NAME" == "osx" ]; then
    if [ ! -d overlay-audio-unit ]; then
        git clone \
            $github_org/overlay-audio-unit.git overlay-audio-unit
        cd overlay-audio-unit
        sed -i '' s/SLVERSION_N/$version_n/ StudioLink/StudioLink.jucer
        wget https://github.com/julianstorer/JUCE/archive/$juce.tar.gz
        tar -xzf $juce.tar.gz
        rm -Rf JUCE
        mv JUCE-$juce JUCE
        ./build.sh
        cd ..
    fi
fi


# Build overlay-audio-unit plugin (osx only)
#-----------------------------------------------------------------------------
if [ "$TRAVIS_OS_NAME" == "osx" ]; then
    if [ ! -d overlay-onair-au ]; then
        git clone \
            $github_org/overlay-onair-au.git overlay-onair-au
        cd overlay-onair-au
        sed -i '' s/SLVERSION_N/$version_n/ StudioLinkOnAir/StudioLinkOnAir.jucer
        cp -a ../overlay-audio-unit/JUCE .
        ./build.sh
        cd ..
    fi
fi


# Build standalone app bundle (osx only)
#-----------------------------------------------------------------------------
if [ "$TRAVIS_OS_NAME" == "osx" ]; then
    if [ ! -d overlay-standalone-osx ]; then
        git clone \
            $github_org/overlay-standalone-osx.git overlay-standalone-osx
        cp -a my_include/re overlay-standalone-osx/StudioLinkStandalone/
        cp -a my_include/baresip.h \
            overlay-standalone-osx/StudioLinkStandalone/
        cd overlay-standalone-osx
        sed -i '' s/SLVERSION_N/$version_n/ StudioLinkStandalone/Info.plist
        ./build.sh
        cd ..
    fi
fi


# Testing and prepare release upload
#-----------------------------------------------------------------------------

./studio-link-standalone -t

if [ "$TRAVIS_OS_NAME" == "linux" ]; then
    ldd studio-link-standalone
    mkdir -p studio-link.lv2
    cp -a overlay-lv2/studio-link.so studio-link.lv2/
    cp -a overlay-lv2/*.ttl studio-link.lv2/
    cp -a overlay-lv2/README.md studio-link.lv2/
    zip -r studio-link-plugin-linux studio-link.lv2

    mkdir -p studio-link-onair.lv2
    cp -a overlay-onair-lv2/studio-link-onair.so studio-link-onair.lv2/
    cp -a overlay-onair-lv2/*.ttl studio-link-onair.lv2/
    cp -a overlay-onair-lv2/README.md studio-link-onair.lv2/
    zip -r studio-link-plugin-onair-linux studio-link-onair.lv2

    zip -r studio-link-standalone-linux studio-link-standalone
else
    otool -L studio-link-standalone
    cp -a ~/Library/Audio/Plug-Ins/Components/StudioLink.component StudioLink.component
    cp -a ~/Library/Audio/Plug-Ins/Components/StudioLinkOnAir.component StudioLinkOnAir.component
    mv overlay-standalone-osx/build/Release/StudioLinkStandalone.app StudioLinkStandalone.app
    if [ "$CIRCLECI" != "true" ]; then
    codesign -f --verbose -s "Developer ID Application: Sebastian Reimers (CX34XZ2JTT)" --keychain ~/Library/Keychains/sl-build.keychain StudioLinkStandalone.app
    fi
    sed $sed_opt s/ITSR:\ StudioLinkOnAir/StudioLinkOnAir\ \(ITSR\)/ StudioLinkOnAir.component/Contents/Info.plist # Reaper 5.70 Fix
    zip -r studio-link-plugin-osx StudioLink.component
    zip -r studio-link-plugin-onair-osx StudioLinkOnAir.component
    zip -r studio-link-standalone-osx StudioLinkStandalone.app
    #security delete-keychain ~/Library/Keychains/sl-build.keychain
fi
