import React, { useState, useEffect } from 'react';
import './App.css';

// replace with dns after>
const API_URL = 'http://localhost:5000';

function App() {
    const [status, setStatus] = useState(null);
    const [loading, setLoading] = useState(true);

    const fetchStatus = async () => {
        setLoading(true);
        try {
            const response = await fetch(`${API_URL}/status`);
            const data = await response.json();
            setStatus(data);
        } catch (error) {
            console.error("Failed to fetch status:", error);
            setStatus(null);
        }
        setLoading(false);
    };

    const handleFailover = async () => {
        if (window.confirm("Are you sure you want to initiate a failover?")) {
            try {
                const response = await fetch(`${API_URL}/initiate-failover`, { method: 'POST' });
                const data = await response.json();
                alert(data.message);
                fetchStatus();
            } catch (error) {
                console.error("Failover initiation failed:", error);
                alert("Failed to initiate failover.");
            }
        }
    };

    useEffect(() => {
        fetchStatus();
    }, []);

    return (
        <div className="App">
            <header className="App-header">
                <h1>Cloud Disaster Recovery Dashboard</h1>
            </header>
            <main className="container">
                {loading ? <p>Loading system status...</p> :
                    !status ? <p className="error">Could not load system status. Is the backend running?</p> :
                        (
                            <div className="status-grid">
                                <div className="site-card primary">
                                    <h2>Primary Site ({status.primarySite.region})</h2>
                                    <p>Database Status: <span className="status-badge">{status.primarySite.databaseStatus}</span></p>
                                </div>
                                <div className="site-card dr">
                                    <h2>DR Site ({status.drSite.region})</h2>
                                    <p>Database Status: <span className="status-badge">{status.drSite.databaseStatus}</span></p>
                                </div>
                            </div>
                        )
                }
                <div className="actions">
                    <button onClick={fetchStatus} disabled={loading}>Refresh Status</button>
                    <button className="failover-button" onClick={handleFailover} disabled={loading}>
                        Initiate Failover
                    </button>
                </div>
            </main>
        </div>
    );
}

export default App;