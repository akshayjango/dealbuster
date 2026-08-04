const https = require('https');
const fs = require('fs');

const runId = '30941528823';

function getJson(url) {
  return new Promise((resolve, reject) => {
    https.get(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch(e) {
          reject(new Error('Failed to parse JSON: ' + data.substring(0, 100)));
        }
      });
    }).on('error', reject);
  });
}

function getLogRedirect(url) {
  return new Promise((resolve, reject) => {
    https.get(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
      }
    }, (res) => {
      if (res.statusCode === 302 || res.statusCode === 307) {
        resolve(res.headers.location);
      } else {
        let body = '';
        res.on('data', chunk => body += chunk);
        res.on('end', () => {
          reject(new Error(`Failed to get redirect. Status: ${res.statusCode}. Body: ${body.substring(0, 200)}`));
        });
      }
    }).on('error', reject);
  });
}

function getRawText(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
    }).on('error', reject);
  });
}

async function main() {
  try {
    console.log(`Fetching jobs for run ${runId}...`);
    const jobsData = await getJson(`https://api.github.com/repos/akshayjango/dealbuster/actions/runs/${runId}/jobs`);
    if (!jobsData.jobs || jobsData.jobs.length === 0) {
      console.log('No jobs found.');
      return;
    }
    const job = jobsData.jobs[0];
    const jobId = job.id;
    console.log(`Job found: ${job.name} (ID: ${jobId}, Conclusion: ${job.conclusion})`);
    
    console.log(`Fetching redirect URL for job logs...`);
    const redirectUrl = await getLogRedirect(`https://api.github.com/repos/akshayjango/dealbuster/actions/jobs/${jobId}/logs`);
    console.log('Log URL located. Fetching logs text...');
    
    const logs = await getRawText(redirectUrl);
    const lines = logs.split('\n');
    console.log(`Total lines in log: ${lines.length}`);
    
    // Print the last 150 lines
    const lastLines = lines.slice(-150);
    console.log('\n--- LAST 150 LINES OF LOG ---');
    console.log(lastLines.join('\n'));
    
  } catch (err) {
    console.error('Error:', err.message);
  }
}

main();
