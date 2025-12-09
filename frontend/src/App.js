// frontend/src/App.js

import React, { useState, useEffect, useCallback } from 'react';
import './App.css';

// The API URL will be read from the .env file
const API_URL = process.env.REACT_APP_API_URL || 'http://localhost:5000';

// A mapping for status colors
const statusColors = {
  OPERATIONAL: '#28a745',
  DEGRADED: '#ffc107',
  ERROR: '#dc3545',
  CONFIG_ERROR: '#6c757d',
};

const StatusCard = ({ title, region, details }) => {
  const status = details?.status || 'ERROR';
  return (
    <div className="status-card">
      <div className="card-header">
        <h3>{title}</h3>
        <span>{region}</span>
      </div>
      <div className="card-body">
        <p>
          <span className="status-indicator" style={{ backgroundColor: statusColors[status] }}></span>
          Status: <strong>{status.replace('_', ' ')}</strong>
        </p>
        <p className="details">{details?.details || 'Could not retrieve details.'}</p>
      </div>
    </div>
  );
};

function App() {
  const [statusData, setStatusData] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchStatus = useCallback(async () => {
    console.log("RUNNING THE NEWEST VERSION of fetchStatus! Calling /api/status...");
    setIsLoading(true);
    setError(null);
    try {
      const response = await fetch(`${API_URL}/api/status`);
      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }
      const data = await response.json();
      setStatusData(data);
    } catch (err) {
      console.error("Failed to fetch status:", err);
      setError("Could not connect to the backend service. Please check the connection and try again.");
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchStatus();
    const interval = setInterval(fetchStatus, 30000); // Auto-refresh every 30 seconds
    return () => clearInterval(interval);
  }, [fetchStatus]);

  const handleFailover = async () => {
    if (window.confirm("ARE YOU ABSOLUTELY SURE you want to initiate a failover? This will redirect all user traffic and should only be done in a confirmed, major outage.")) {
      try {
        const response = await fetch(`${API_URL}/api/initiate-failover`, { method: 'POST' });
        const data = await response.json();
        
        if (response.ok) {
          alert(`SUCCESS: ${data.message}\n\nYou can monitor the progress in the AWS Step Functions console with this execution ARN:\n${data.executionArn}`);
        } else {
          alert(`ERROR: ${data.message || 'An unknown error occurred.'}`);
        }

        fetchStatus(); // Refresh the main dashboard status
      } catch (err) {
        alert("Failed to connect to the backend to initiate failover. Is the backend running?");
      }
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <h1>Cloud Disaster Recovery Dashboard</h1>
        {statusData && <span className="last-checked">Last checked: {new Date(statusData.lastChecked).toLocaleTimeString()}</span>}
      </header>
      
      <main className="container">
        {isLoading && <p>Loading system status...</p>}
        {error && <p className="error-message">{error}</p>}
        
        {statusData && !isLoading && !error && (
          <>
            <div className="overall-status-banner" style={{ borderLeftColor: statusColors[statusData.overallStatus] }}>
              <h2>Overall System Status: <strong>{statusData.overallStatus}</strong></h2>
            </div>

            <div className="status-grid">
              <StatusCard title="Primary Site" region={statusData.primarySite.region} details={statusData.primarySite.replicationStatus} />
              <div className="status-card">
                 <div className="card-header">
                    <h3>Backup Status</h3>
                    <span>S3 Bucket: {statusData.primarySite.bucketName}</span>
                 </div>
                 <div className="card-body">
                    <p>
                        <span className="status-indicator" style={{ backgroundColor: statusColors[statusData.backupDetails.freshness_status] }}></span>
                        Freshness: <strong>{statusData.backupDetails.freshness_status}</strong>
                    </p>
                    <p className="details">Last Backup: {statusData.backupDetails.last_backup_time}</p>
                    <p className="details">File: {statusData.backupDetails.last_backup_file}</p>
                 </div>
              </div>
            </div>

            <div className="actions">
              <button onClick={fetchStatus} disabled={isLoading}>Refresh Status</button>
              <button className="failover-button" onClick={handleFailover} disabled={isLoading}>
                Initiate Failover
              </button>
            </div>
          </>
        )}
      </main>
    </div>
  );
}

export default App;