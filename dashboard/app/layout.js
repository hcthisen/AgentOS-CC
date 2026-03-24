import './globals.css'

export const metadata = {
  title: 'AgentOS Dashboard',
  description: 'Security & health monitoring for AgentOS-CC',
}

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
