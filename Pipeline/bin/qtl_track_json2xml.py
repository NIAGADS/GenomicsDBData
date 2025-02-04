#!/usr/bin/env python3
import argparse
import json
import xml.etree.ElementTree as ET
from os import path

TYPE_ID = 53014 # Genetic variation
SUBTYPE_ID = 768 # QTL
EXT_DB_RLS_ID = 19 # NIAGADS/current

def run():  
    outputFile = path.join(args.outputPath, 'protocol_app_node.xml')
    strBuffer = ""
    root = ET.Element("root")
    tree = ET.ElementTree(root)
    base = tree.getroot()
    with open(args.input, 'r') as fh: #, open(outputFile, 'w') as ofh:
        for line in fh:
            line = line.strip()
            metadata = json.loads(line)
            sourceId = metadata['track_id']
            node = ET.Element("Study::ProtocolAppNode")
            ET.SubElement(node, "source_id" ).text = metadata['track_id']
            ET.SubElement(node, "type_id").text = str(TYPE_ID)
            ET.SubElement(node, "subtype_id").text = str(SUBTYPE_ID)
            ET.SubElement(node, "name").text = metadata['name']
            ET.SubElement(node, "description").text = metadata['description']
            ET.SubElement(node, "uri").text = metadata['url']
            ET.SubElement(node, "external_database_release_id").text = str(EXT_DB_RLS_ID)
            ET.SubElement(node, "attribution").text = args.attribution
            ET.SubElement(node, "track_summary").text = line
            
            studyLink = ET.SubElement(node, "Study::StudyLink")
            ET.SubElement(studyLink, "study_id").text = str(args.studyId)
            
            subtree = ET.ElementTree(node)
            base.append(subtree.getroot())
            
        ET.indent(tree, space="\t", level=0)
        tree.write(path.join(args.outputPath, 'protocol_app_node.xml'))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="translate QTL FILER track metadata in JSON format to XML for LoadGUSXml")
    parser.add_argument('--input', help="full path to metadata (JSON) file", required=True)
    parser.add_argument('--attribution', help="attribution (Author Year|PMID=X)", required=True)
    parser.add_argument('--studyId', help="Study.Study study_id for study linking node", required=True)
    parser.add_argument('--outputPath', required=True)
    
    args = parser.parse_args()
    
    run()
