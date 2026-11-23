# The example links on the /documentation page, which are served without an
# API key so the documentation can be tried from a browser. A request
# qualifies only if it is a GET or HEAD for exactly one of these paths with
# exactly these query parameters (see LinkedData::Security::Authorization);
# anything else, including the links in the responses, needs an API key.
#
# Keep this list in step with the links marked `keyless-example` in
# views/documentation/documentation.haml:
# test/controllers/test_keyless_doc_examples.rb fails when the two differ.
KEYLESS_DOC_EXAMPLES = [
  "/search?q=melanoma",
  "/search?q=melanoma&ontology=NCIT&subtree_root_id=http%3a%2f%2fncicb.nci.nih.gov%2fxml%2fowl%2fEVS%2fThesaurus.owl%23C3224",
  "/search?q=melanoma&ontologies=NCIT,GO&roots_only=true",
  "/property_search?q=has%20dimension",
  "/annotator?text=Melanoma+is+a+malignant+tumor+of+melanocytes+which+are+found+predominantly+in+skin+but+also+in+the+bowel+and+the+eye.",
  "/recommender?input=Melanoma%20is%20a%20malignant%20tumor%20of%20melanocytes%20which%20are%20found%20predominantly%20in%20skin%20but%20also%20in%20the%20bowel%20and%20the%20eye",
  "/recommender?input=leukocyte,phagocyte,motile%20cell,metabolising%20cell,dendritic%20cell,%20pipette&input_type=2",
  "/recommender?input=leukocyte,phagocyte,motile%20cell,metabolising%20cell,dendritic%20cell,%20pipette&input_type=2&ontologies=UBERON,CL,NCIT,EFO",
  "/recommender?input=leukocyte,phagocyte,motile%20cell,metabolising%20cell,dendritic%20cell,%20pipette&input_type=2&output_type=2",
  "/recommender?input=Melanoma%20is%20a%20malignant%20tumor%20of%20melanocytes%20which%20are%20found%20predominantly%20in%20skin%20but%20also%20in%20the%20bowel%20and%20the%20eye&wa=0&wd=0&ws=0",
  "/analytics",
  "/analytics?month=4&year=2014",
  "/ontologies/NCIT/analytics"
].freeze
