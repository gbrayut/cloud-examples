CREATE OR REPLACE PROCEDURE mydataset.getCorpusWordCount(w STRING, c STRING)
BEGIN
    SELECT word, word_count
    FROM `bigquery-public-data.samples.shakespeare`
    WHERE word = w AND corpus = c
    LIMIT 1;
END

/*
query = """
  CALL `myproject.mydataset.getCorpusWordCount`('the','%s');
""" % (corpus)
*/
