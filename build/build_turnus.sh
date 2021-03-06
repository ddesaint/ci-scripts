#!/bin/bash
# Usage:
NBARGS=3
function print_usage() {
    echo
    echo "Usage: $0 <working_directory> <feature_dir> <plugin_dir> [<plugin_dir> <plugin_dir> ...]"
    echo "    <working_directory>           Path to folder used to perform build & tests"
    echo "    <features_dir>                Path to eclipse features folder"
    echo "    <plugin_dir>                  Path(s) to folder(s) containing eclipse plugins directories"
}

if [ $# -lt $NBARGS ]; then
    print_usage
    exit $E_BADARGS
fi

[ ! -d "$2" ] && echo "Missing features directory" && print_usage && exit $E_BADARGS
[ ! -d "$3" ] && echo "Missing plugins directory" && print_usage && exit $E_BADARGS

# Import constants
source $(dirname $0)/../utils/defines.sh
setupEclipse $1
SOURCESFEATUREDIR=$2

echo "***START*** $(date -R) Build type: $BUILDTYPE"
rm -fr $BUILDDIR
mkdir -p $PLUGINSDIR
mkdir -p $FEATURESDIR

cp -ur $SOURCESFEATUREDIR/* $FEATURESDIR

# Remove the 2 first arg from command line
shift 2
# Loop over resulting cli arguments
for arg; do
    cp -ur $arg/* $PLUGINSDIR
done

rm -fr $PLUGINSDIR/**/xtend-gen/*
rm -fr $PLUGINSDIR/**/src-gen/*
rm -fr $PLUGINSDIR/**/bin/*

echo ""
echo "****************************************************************"
echo "*             Generates Java sources from Xtend                *"
echo "****************************************************************"
echo ""

##
xtendoutputdir="xtend-output"
pushd $PLUGINSDIR
java -cp $ECLIPSECP:$SOURCEFOLDERS \
    org.eclipse.xtend.core.compiler.batch.Main \
    -useCurrentClassLoader \
    -d ./${xtendoutputdir} \
    "$SOURCEFOLDERS"

for xtendfile in $(find -name "*.xtend"); do
    # The path of the generated java file, under ${xtendoutputdir} folder
    fromJavaFile=$(echo $xtendfile | sed -e 's/.xtend/.java/g' | sed -e 's/\/src\//%/g' | cut -d'%' -f2)
    # The path where this java file should be moved before running java compilation
    toJavaFile=$(echo $xtendfile | sed -e 's/.xtend/.java/g' | sed -e 's/\/src\//\/xtend-gen\//g')
    mkdir -p $(dirname $toJavaFile)
    mv ${xtendoutputdir}/$fromJavaFile $toJavaFile
done

rm -fr $xtendoutputdir
popd

echo ""
echo "****************************************************************"
echo "*                    Launches PDE Build                        *"
echo "****************************************************************"
echo ""

# Define PDE build specific variables
BUILDFILE=$(echo $ECLIPSE_BUILD/plugins/org.eclipse.pde.build_*)/scripts/build.xml
KEEPONLYLATESTVERSIONS=true # Set to false when a Release build will be defined

if [ "$BUILDTYPE" == "tests" ]; then
    PDEBUILDTYPE=I
    REPONAME="Turnus tests repository"
    NBUILDSTOKEEP=3
else
    PDEBUILDTYPE=R
    REPONAME="Turnus release"
    NBUILDSTOKEEP=999999
fi

mkdir -p $BUILDDIR

# This will be used as default name for the top level folder of
# build features and plugins. Needs to rename it
ARCHIVEPREFIX=turnus_latest

BUILDID="${BUILDTYPE}_build"

TURNUS_MAINFEATURE_ID="co.turnus"
TURNUS_PROFILERFEATURE_ID="co.turnus.profiler"
ARTIFACTSFOLDER="final_artifacts"

# For information on following properties:
# - open build.properties from <eclipse_dir>/plugins/org.eclipse.pde.build_*/templates/headless-build/build.properties
# - http://help.eclipse.org/kepler/index.jsp?topic=%2Forg.eclipse.pde.doc.user%2Ftasks%2Fpde_feature_build.htm&cp=4_2_0_1
$ECLIPSE_BUILD/eclipse   -nosplash -consoleLog -application org.eclipse.ant.core.antRunner \
                        -buildfile $BUILDFILE \
                        -DskipFetch=true \
                        -DtopLevelElementId=$TURNUS_MAINFEATURE_ID \
                        -DtopLevelElementType=feature \
                        -DjavacSource=1.7 -DjavacTarget=1.7 \
                        -DbaseLocation=$ECLIPSE_BUILD \
                        -DpluginPath=$ECLIPSE_BUILD:$BUILDDIR \
                        -DbuildDirectory=$BUILDDIR \
                        -Dbase=$BUILDDIR \
                        -DbuildId=$BUILDID \
                        -DbuildType=$PDEBUILDTYPE \
                        -DbuildLabel=$ARTIFACTSFOLDER \
                        -DarchivePrefix=$ARCHIVEPREFIX \
                        -DcollectingFolder=binary_output \
                        -DoutputUpdateJars=true



$ECLIPSE_BUILD/eclipse   -nosplash -consoleLog -application org.eclipse.ant.core.antRunner \
                        -buildfile $BUILDFILE \
                        -DskipFetch=true \
                        -DtopLevelElementId=$TURNUS_PROFILERFEATURE_ID \
                        -DtopLevelElementType=feature \
                        -DjavacSource=1.7 -DjavacTarget=1.7 \
                        -DbaseLocation=$ECLIPSE_BUILD \
                        -DpluginPath=$ECLIPSE_BUILD:$BUILDDIR \
                        -DbuildDirectory=$BUILDDIR \
                        -Dbase=$BUILDDIR \
                        -DbuildId=$BUILDID \
                        -DbuildType=$PDEBUILDTYPE \
                        -DbuildLabel=$ARTIFACTSFOLDER \
                        -DarchivePrefix=$ARCHIVEPREFIX \
                        -DcollectingFolder=binary_output \
                        -DoutputUpdateJars=true

echo ""
echo "****************************************************************"
echo "*                  Builds the p2 repository                    *"
echo "****************************************************************"

LOCALREPO=$TURNUS_WD/repository.$BUILDTYPE
mkdir -p $LOCALREPO

echo ""
echo "-> Extract built zip file to " $LOCALREPO
# Unzip the built zip, the created folder is $ARCHIVEPREFIX
unzip -o $BUILDDIR/$ARTIFACTSFOLDER/$TURNUS_MAINFEATURE_ID-$BUILDID.zip -d $LOCALREPO
unzip -o $BUILDDIR/$ARTIFACTSFOLDER/$TURNUS_PROFILERFEATURE_ID-$BUILDID.zip -d $LOCALREPO

echo ""
#echo "-> Move unit tests zip archive to a place where it will be archivable"
#rm -f $TURNUS_WD/*.zip
#mv $BUILDDIR/$ARTIFACTSFOLDER/$TURNUS_PROFILERFEATURE_ID-$BUILDID.zip $TURNUS_WD

pushd $LOCALREPO > /dev/null

echo "archive prefix: " $ARCHIVEPREFIX " ; currentbuild: " $CURRENTBUILD



# Load version number computed from the build
featureFile=$(echo $(basename $ARCHIVEPREFIX/features/${TURNUS_MAINFEATURE_ID}*))
VERSION=$(echo ${featureFile%.*} | cut -d'_' -f2)
CURRENTBUILD="${TURNUS_MAINFEATURE_ID}_${VERSION}"

echo ""
echo "-> Rename $ARCHIVEPREFIX into $CURRENTBUILD"
# Rename it to its final name
mv $ARCHIVEPREFIX $CURRENTBUILD

# Initialize a p2 repository in the extracted folder
echo ""
echo "-> Transform $CURRENTBUILD into a standard p2 repository"

$P2ADMIN -application org.eclipse.equinox.p2.publisher.FeaturesAndBundlesPublisher \
    -metadataRepository file:$(pwd)/${CURRENTBUILD} \
    -artifactRepository file:$(pwd)/${CURRENTBUILD} \
    -source $(pwd)/${CURRENTBUILD} \
    -compress

# Print p2.index files...
p2Index=<<EOF
version = 1
metadata.repository.factory.order = compositeContent.xml,\!
artifact.repository.factory.order = compositeArtifacts.xml,\!
EOF
# ... in the current repository
echo $p2Index > $(pwd)/${CURRENTBUILD}/p2.index
# ... in the top level composite repository
echo $p2Index > ./p2.index

# Create a tempoary file defining the category we will publish
pushd ${CURRENTBUILD} > /dev/null
CATEGORY=$TURNUS_MAINFEATURE_ID.category.$BUILDTYPE
TMPFILE=$(mktemp)
cat > $TMPFILE <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<site>
    <category-def name="$CATEGORY" label="${REPONAME}"/>
    <feature url="$(ls features/${TURNUS_MAINFEATURE_ID}*)" id="${TURNUS_MAINFEATURE_ID}" version="${VERSION}">
        <category name="$CATEGORY"/>
    </feature>
   <feature url="$(ls features/${TURNUS_PROFILERFEATURE_ID}*)" id="${TURNUS_PROFILERFEATURE_ID}" version="${VERSION}">
        <category name="$CATEGORY"/>
    </feature>
</site>
EOF
popd > /dev/null

# Publish category for the current build
echo ""
echo "-> Register $CURRENTBUILD into category ${REPONAME}"
$P2ADMIN -application org.eclipse.equinox.p2.publisher.CategoryPublisher \
    -metadataRepository file:$(pwd)/${CURRENTBUILD} \
    -categoryDefinition file:$TMPFILE \
    -categoryQualifier -compress

# Delete oldest builds before creating the composite repo

echo ""
echo "-> Delete useless builds (all but the ${NBUILDSTOKEEP} last)"
for oldDirectory in $(find -mindepth 1 -maxdepth 1 -type d -name "${TURNUS_MAINFEATURE_ID}_*" | sort | head -n -${NBUILDSTOKEEP}); do
    echo "Delete ${oldDirectory}"
    rm -fr "${oldDirectory}"
done
for oldDirectory in $(find -mindepth 1 -maxdepth 1 -type d -name "${TURNUS_PROFILERFEATURE_ID}_*" | sort | head -n -${NBUILDSTOKEEP}); do
    echo "Delete ${oldDirectory}"
    rm -fr "${oldDirectory}"
done

# Delete repository indexes, will be fully re-generated in the next command
rm -fr compositeArtifacts.* compositeContent.*

echo ""
echo "-> Create p2 composite repository (top level, references all sub-repositories)"
$P2ADMIN -application org.eclipselabs.equinox.p2.composite.repository \
    -location file:$(pwd) \
    -add $(echo ${TURNUS_MAINFEATURE_ID}_* | sed -e "s/ /,/g") "," $(echo ${TURNUS_PROFILERFEATURE_ID}_* | sed -e "s/ /,/g")\
    -repositoryName "$REPONAME" \
    -compressed

popd > /dev/null

# We don't want to install just built releases into eclipse.runtime
if [ "$BUILDTYPE" == "releases" ]; then
    exit 0
fi

echo ""
echo "****************************************************************"
echo "*     Installs Turnus plugins into eclipse runtime             *"
echo "****************************************************************"

echo ""
echo "-> Uninstall old core feature"
$P2ADMIN -application org.eclipse.equinox.p2.director \
  -destination $ECLIPSE_BUILD \
  -uninstallIU ${TURNUS_MAINFEATURE_ID}.feature.group \
|| echo -e "\n*** There is no existing Orcc feature to uninstall. This is probably the first time this script is \n\
launched since last eclipse reinstall. Please ignore the previous error message. ***"

echo ""
echo "-> Uninstall old profiler feature"
$P2ADMIN -application org.eclipse.equinox.p2.director \
  -destination $ECLIPSE_BUILD \
  -uninstallIU ${TURNUS_PROFILERFEATURE_ID}.feature.group \
|| echo -e "\n*** There is no existing Orcc feature to uninstall. This is probably the first time this script is \n\
launched since last eclipse reinstall. Please ignore the previous error message. ***"

#TURNUS_PROFILERFEATURE_ID

echo ""
echo "-> Install new core feature"
$P2ADMIN -application org.eclipse.equinox.p2.director \
  -destination $ECLIPSE_BUILD \
  -artifactRepository file:$LOCALREPO \
  -metadataRepository file:$LOCALREPO \
  -repository $ECLIPSEREPOSITORY \
  -installIU ${TURNUS_MAINFEATURE_ID}.feature.group

echo ""
echo "-> Install new profiler feature"
$P2ADMIN -application org.eclipse.equinox.p2.director \
  -destination $ECLIPSE_BUILD \
  -artifactRepository file:$LOCALREPO \
  -metadataRepository file:$LOCALREPO \
  -repository $ECLIPSEREPOSITORY \
  -installIU ${TURNUS_PROFILERFEATURE_ID}.feature.group

echo ""
echo "***END*** $0 $(date -R)"
