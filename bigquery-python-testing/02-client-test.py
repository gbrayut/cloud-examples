# Testing bigquery.Client re-use
from google.cloud import bigquery

client = bigquery.Client()  # Initialize once and re-use for multiple queries
iterations = 3      # 30 is another good testing value when verbose = False
verbose = False     # True to see each individual QueryJob details

def bqtest(corpus):
    #client = bigquery.Client() # This would have higher latency since client would not be re-used
    job_config = None
    
    # "noop" query with little/no SQL complilation or execution time
    noop = "SELECT 1"
    
    # Sample dataset query: How often 'the' appears in specific corpus of shakespear
    testquery = """
        SELECT word, word_count
        FROM `bigquery-public-data.samples.shakespeare`
        WHERE word = '%s' AND corpus = '%s'
        LIMIT 1
    """ % ('the',corpus)

    # Uncomment below to disable query cache https://cloud.google.com/bigquery/docs/samples/bigquery-query-no-cache#bigquery_query_no_cache-python
    # job_config = bigquery.job.QueryJobConfig(use_query_cache=False)
    job = client.query(noop, job_config=job_config)

    if(verbose):
      # Uncomment these when using testquery to see the results for each run
      #row = next(job.result())
      #word = row['word']
      #count = row['word_count']
      #print(f'Results:  {corpus:<12} | {word} | {count}')
      print(f'Duration: {job.ended-job.created}')
      print(f'Bytes:    {job.total_bytes_processed:,} | {job.total_bytes_billed:,}')
      print(f'Cached:   {job.cache_hit}')
      print('-'*60)

if __name__ == "__main__":
    import timeit
    setup = "from __main__ import bqtest"
    for idx,val in enumerate(['hamlet','coriolanus']): #,'kinghenryv','2kinghenryiv','kinglear']):
        t = timeit.Timer("bqtest('{:s}')".format(val), setup=setup).timeit(number=iterations)
        print('The total time for {c:} {v:>12s} iterations is {t:0.4f} and average {a:0.4f} seconds'.format(c=iterations,v=val, t=t, a=t/iterations))
