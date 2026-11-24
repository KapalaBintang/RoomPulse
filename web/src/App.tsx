import React, { useState } from 'react';
import { AuthProvider, useAuth } from './context/AuthContext';
import { Navbar } from './components/Navbar';
import { LoginPage } from './pages/LoginPage';
import { RoomsPage } from './pages/RoomsPage';
import { RoomDetailPage } from './pages/RoomDetailPage';
import { MyBookingsPage } from './pages/MyBookingsPage';
import { DevSimulatorPage } from './pages/DevSimulatorPage';
import { AdminPage } from './pages/AdminPage';

const AppContent: React.FC = () => {
  const { user } = useAuth();
  const [currentTab, setCurrentTab] = useState<string>('rooms');
  const [selectedRoomId, setSelectedRoomId] = useState<string | null>(null);

  const handleSelectRoom = (roomId: string) => {
    setSelectedRoomId(roomId);
    setCurrentTab('room-detail');
  };

  return (
    <div className="min-h-screen flex flex-col bg-slate-50 text-slate-900">
      <Navbar currentTab={currentTab} setCurrentTab={setCurrentTab} />

      <main className="flex-1">
        {currentTab === 'login' && (
          <LoginPage onSuccess={() => setCurrentTab('rooms')} />
        )}

        {currentTab === 'rooms' && (
          <RoomsPage onSelectRoom={handleSelectRoom} />
        )}

        {currentTab === 'room-detail' && selectedRoomId && (
          <RoomDetailPage
            roomId={selectedRoomId}
            onBack={() => setCurrentTab('rooms')}
            onBookingSuccess={() => setCurrentTab('my-bookings')}
          />
        )}

        {currentTab === 'my-bookings' && (
          user ? <MyBookingsPage /> : <LoginPage onSuccess={() => setCurrentTab('my-bookings')} />
        )}

        {currentTab === 'simulator' && (
          <DevSimulatorPage />
        )}

        {currentTab === 'admin' && (
          <AdminPage />
        )}
      </main>

      <footer className="bg-white border-t border-slate-200 py-6 text-center text-xs text-slate-400">
        <p>RoomPulse — Sensor-Verified Study Room Booking System • STACK 2026 Semifinal Prototype</p>
      </footer>
    </div>
  );
};

export function App() {
  return (
    <AuthProvider>
      <AppContent />
    </AuthProvider>
  );
}

export default App;
