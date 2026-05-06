import React from 'react';

export default function GalleryView({ children }) {
  return (
    <div style={{
      columns: '3 200px',
      columnGap: '12px',
      padding: '12px 0',
    }}>
      {React.Children.map(children, (child, i) => (
        <div key={i} style={{
          breakInside: 'avoid',
          marginBottom: '12px',
          borderRadius: '6px',
          overflow: 'hidden',
        }}>
          {child}
        </div>
      ))}
    </div>
  );
}
